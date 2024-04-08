#pragma once
#include <deque>
#include <string>

#ifdef _MSC_VER
#define strncasecmp _strnicmp
#endif

#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {
    inline size_t       CRLF_LEN    = 2;
    inline size_t       HEAD_SIZE   = 24;
    inline const char*  RDS_CRLF    = "\r\n";

    class rdscodec : public codec_base {
    public:
        virtual int load_packet(size_t data_len) {
            if (!m_slice) return 0;
            return data_len;
        }

        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            int n = lua_gettop(L);
            uint32_t session_id = lua_tointeger(L, index++);
            char* head = (char*)m_buf->peek_space(HEAD_SIZE);
            m_buf->pop_space(sprintf(head, "*%d\r\n", n - index + 1));
            for (int i = index; i <= n; ++i) {
                encode_bulk_string(L, i);
            }
            sessions.push_back(session_id);
            return m_buf->data(len);
        }

        virtual size_t decode(lua_State* L) {
            int top = lua_gettop(L);
            size_t osize = m_slice->size();
            string_view buf = m_slice->contents();
            lua_pushinteger(L, sessions.empty() ? 0 : sessions.front());
            parse_redis_packet(L, buf);
            if (!sessions.empty()) sessions.pop_front();
            m_packet_len = osize - buf.size();
            m_slice->erase(m_packet_len);
            return lua_gettop(L) - top;
        }

        void set_codec(codec_base* codec) {
            m_jcodec = codec;
        }

    protected:
        void parse_redis_success(lua_State* L, string_view line) {
            lua_pushboolean(L, true);
            lua_pushlstring(L, line.data(), line.size());
        }

        void parse_redis_error(lua_State* L, string_view line) {
            lua_pushboolean(L, false);
            lua_pushlstring(L, line.data(), line.size());
        }

        void parse_redis_integer(lua_State* L, string_view line, bool rootable = false) {
            if (rootable) lua_pushboolean(L, true);
            lua_pushinteger(L, atoll(line.data()));
        }

        void parse_redis_string(lua_State* L, string_view line, string_view& buf, bool rootable = false) {
            int64_t length = atoll(line.data());
            if (length >= 0) {
                string_view nline;
                if (!read_line(buf, nline))
                    throw length_error("redis text not full");
                if (!strncasecmp(nline.data(), "[js]", 4)) {
                    nline.remove_prefix(4);
                    m_jcodec->decode(L, (uint8_t*)nline.data(), nline.size());
                } else {
                    lua_pushlstring(L, nline.data(), nline.size());
                }
            }
            else {
                lua_pushnil(L);
            }
            if (rootable) {
                lua_pushboolean(L, true);
                lua_insert(L, -2);
            }
        }

        void parse_redis_array(lua_State* L, string_view line, string_view& buf, bool rootable = false) {
            int64_t length = atoll(line.data());
            if (length >= 0) {
                lua_createtable(L, 0, 4);
                for (int i = 1; i <= length; ++i) {
                    string_view line;
                    if (!read_line(buf, line)) throw length_error("redis text not full");
                    switch (line[0]) {
                    case ':':
                        parse_redis_integer(L, line.substr(1));
                        break;
                    case '$':
                        parse_redis_string(L, line.substr(1), buf);
                        break;
                    case '*':
                        parse_redis_array(L, line.substr(1), buf);
                        break;
                    default:
                        throw lua_exception("invalid redis format");
                        break;
                    }
                    lua_seti(L, -2, i);
                }
            }
            else {
                lua_pushnil(L);
            }
            if (rootable) {
                lua_pushboolean(L, true);
                lua_insert(L, -2);
            }
        }

        void parse_redis_packet(lua_State* L, string_view& buf) {
            string_view line;
            if (!read_line(buf, line)) throw length_error("redis text not full");
            switch (line[0]) {
            case '+':
                parse_redis_success(L, line.substr(1));
                break;
            case '-':
                parse_redis_error(L, line.substr(1));
                break;
            case ':':
                parse_redis_integer(L, line.substr(1), true);
                break;
            case '$':
                parse_redis_string(L, line.substr(1), buf, true);
                break;
            case '*':
                parse_redis_array(L, line.substr(1), buf, true);
                break;
            default:
                throw lua_exception("invalid redis format");
                break;
            }
        }

        bool read_line(string_view& buf, string_view& line) {
            size_t pos = buf.find(RDS_CRLF);
            if (pos != string_view::npos) {
                line = buf.substr(0, pos);
                buf.remove_prefix(pos + CRLF_LEN);
                return true;
            }
            return false;
        }

        void number_encode(double value) {
            auto svalue = std::to_string(value);
            char* head = (char*)m_buf->peek_space(HEAD_SIZE + svalue.size());
            m_buf->pop_space(sprintf(head, "$%zd\r\n%s\r\n", svalue.size(), svalue.c_str()));
        }

        void integer_encode(int64_t integer) {
            auto svalue = std::to_string(integer);
            char* head = (char*)m_buf->peek_space(HEAD_SIZE + svalue.size());
            m_buf->pop_space(sprintf(head, "$%zd\r\n%s\r\n", svalue.size(), svalue.c_str()));
        }

        void string_encode(lua_State* L, int idx) {
            size_t len;
            const char* data = lua_tolstring(L, idx, &len);
            char* head = (char*)m_buf->peek_space(HEAD_SIZE + len);
            m_buf->pop_space(sprintf(head, "$%zd\r\n%s\r\n", len, data));
        }

        void table_encode(lua_State* L, int idx) {
            size_t len;
            char* body = (char*)m_jcodec->encode(L, idx, &len);
            char* head = (char*)m_buf->peek_space(HEAD_SIZE + len);
            m_buf->pop_space(sprintf(head, "$%zd\r\n[js]%s\r\n", len + 4, body));
        }

        void encode_bulk_string(lua_State* L, int idx) {
            int type = lua_type(L, idx);
            switch (type) {
            case LUA_TSTRING:
                string_encode(L, idx);
                break;
            case LUA_TBOOLEAN: 
                integer_encode(lua_toboolean(L, idx) ? 1 : 0);
                break;
            case LUA_TNUMBER:
                lua_isinteger(L, idx) ? integer_encode(lua_tointeger(L, idx)) : number_encode(lua_tonumber(L, idx));
                break;
            case LUA_TTABLE: 
                table_encode(L, idx);
                break;
            default:
                m_buf->write("$-1\r\n");
                break;
            }
        }

    protected:
        deque<uint32_t> sessions;
        codec_base* m_jcodec = nullptr;
    };
}
