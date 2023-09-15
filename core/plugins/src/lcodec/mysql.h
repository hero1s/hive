#pragma once

#include <deque>
#include "lua_kit.h"

using namespace std;
using namespace luakit;

namespace lcodec {
    // constants
    inline size_t CLIENT_FLAG = 260047;
    inline size_t MAX_PACKET_SIZE = 0xffffff;
    inline size_t CLIENT_PLUGIN_AUTH = 1 << 3;

    // field types
    inline uint16_t MYSQL_TYPE_TINY = 0x01;
    inline uint16_t MYSQL_TYPE_DOUBLE = 0x05;
    inline uint16_t MYSQL_TYPE_NULL = 0x08;
    inline uint16_t MYSQL_TYPE_LONGLONG = 0x08;
    inline uint16_t MYSQL_TYPE_VARCHAR = 0x0f;

    // cmd constants
    const uint8_t COM_SLEEP = 0x00;
    const uint8_t COM_CONNECT = 0x0b;
    const uint8_t COM_STMT_PREPARE = 0x16;
    const uint8_t COM_STMT_CLOSE = 0x19;

    struct mysql_cmd {
        uint8_t  cmd_id;
        size_t session_id;
    };

    class mysqlscodec : public codec_base {
    public:
        mysqlscodec(size_t session_id) {
            sessions.push_back(mysql_cmd{ COM_SLEEP, session_id });
        }

        virtual void clean() {
            sessions.clear();
        }

        virtual const char* name() {
            return "mysql";
        }

        virtual int load_packet(size_t data_len) {
            if (!m_slice) return 0;
            uint32_t* packet_len = (uint32_t*)m_slice->peek(sizeof(uint32_t));
            if (!packet_len) return 0;
            uint32_t length = ((*packet_len) >> 8) + sizeof(uint32_t);
            if (length > data_len) return 0;
            if (!m_slice->peek(length)) return 0;
            return length;
        }

        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            // cmd_id
            uint8_t cmd_id = (uint8_t)lua_tointeger(L, index++);
            // session_id
            size_t session_id = lua_tointeger(L, index++);
            if (cmd_id != COM_CONNECT) {
                return comand_encode(L, cmd_id, session_id, index, len);
            }
            return auth_encode(L, cmd_id, session_id, index, len);
        }

        virtual size_t decode(lua_State* L) {
            int top = lua_gettop(L);
            if (sessions.empty()) throw invalid_argument("invalid mysql data");
            uint32_t payload = *(uint32_t*)m_slice->read<uint32_t>();
            uint32_t length = payload >> 8;
            if (length >= 0xffffff) throw invalid_argument("sharded packet not suppert!");
            mysql_cmd cmd = sessions.front();
            lua_pushinteger(L, cmd.session_id);
            switch (cmd.cmd_id) {
            case COM_SLEEP:
                auth_decode(L);
                break;
            case COM_STMT_PREPARE:
                prepare_decode(L);
                break;
            default:
                command_decode(L);
                break;
            }
            sessions.pop_front();
            return lua_gettop(L) - top;
        }

    protected:
        uint8_t* comand_encode(lua_State* L, uint8_t cmd_id, size_t session_id, int index, size_t* len) {
            m_buf->write<uint8_t>(cmd_id);
            int top = lua_gettop(L);
            int argnum = top - index;
            if (argnum > 1) {
                if (lua_type(L, index) == LUA_TNUMBER) {
                    m_buf->write<uint32_t>(lua_tointeger(L, index++));
                }
                else {
                    size_t data_len;
                    uint8_t* query = (uint8_t*)lua_tolstring(L, index++, &data_len);
                    m_buf->push_data(query, data_len);
                }
            }
            if (argnum > 2) {
                encode_stmt_args(L, index, argnum - 2);
            }
            if (cmd_id != COM_STMT_CLOSE) {
                sessions.push_back(mysql_cmd{ cmd_id, session_id });
            }
            return m_buf->data(len);
        }

        uint8_t* auth_encode(lua_State* L, uint8_t cmd_id, size_t session_id, int index, size_t* len) {
            //4 byte header placeholder
            m_buf->write<uint32_t>(0);
            //4 byte client_flag
            m_buf->write<uint32_t>(CLIENT_FLAG);
            //4 byte max_packet_size
            m_buf->write<uint32_t>(MAX_PACKET_SIZE);
            //1 byte character_set
            m_buf->write<uint8_t>((uint8_t)lua_tointeger(L, index++));
            //23 byte filler(all 0)
            m_buf->pop_space(23);
            // username
            uint8_t* user = (uint8_t*)lua_tolstring(L, index++, len);
            m_buf->push_data(user, *len);
            uint8_t* auth_data = (uint8_t*)lua_tolstring(L, index++, len);
            m_buf->write<uint8_t>(*len);
            m_buf->push_data(auth_data, *len);
            //dbname
            const uint8_t* dbname = (const uint8_t*)lua_tolstring(L, index++, len);
            m_buf->push_data(dbname, *len);
            // header
            uint32_t size = ((m_buf->size() - 4) << 8) | 0xffffff00;
            m_buf->copy(0, (uint8_t*)&size, 4);
            // cmd
            sessions.push_back(mysql_cmd{ cmd_id, session_id });
            return m_buf->data(len);
        }

        size_t command_decode(lua_State* L) {
            return 0;
        }

        size_t prepare_decode(lua_State* L) {
            uint8_t status = *(uint8_t*)m_slice->read<uint8_t>();
            uint32_t statement_id = *(uint32_t*)m_slice->read<uint32_t>();
            uint16_t num_columns = *(uint16_t*)m_slice->read<uint16_t>();
            uint16_t num_params = *(uint16_t*)m_slice->read<uint16_t>();
            uint8_t reserved_1 = *(uint8_t*)m_slice->read<uint8_t>();
            uint16_t warn_params = *(uint16_t*)m_slice->read<uint16_t>();
            return 0;
        }

        size_t auth_decode(lua_State* L) {
            size_t data_len;
            //1 byte protocol version
            uint8_t proto = *(uint8_t*)m_slice->read<uint8_t>();
            //n byte server version
            const char* version = read_cstring(m_slice, data_len);
            //4 byte thread_id
            uint32_t thread_id = *(uint32_t*)m_slice->read<uint32_t>();
            //8 byte auth-plugin-data-part-1
            uint8_t* scramble1 = m_slice->peek(8);
            //8 byte auth-plugin-data-part-1 + 1 byte filler
            m_slice->erase(9);
            //2 byte capability_flags_1
            uint16_t capability_flag_1 = *(uint16_t*)m_slice->read<uint16_t>();
            //1 byte character_set
            uint8_t character_set = *(uint8_t*)m_slice->read<uint8_t>();
            //2 byte status_flags
            uint16_t status_flags = *(uint16_t*)m_slice->read<uint16_t>();
            //2 byte capability_flags_2
            uint16_t capability_flag_2 = *(uint16_t*)m_slice->read<uint16_t>();
            //1 byte character_set
            uint8_t auth_plugin_data_len = *(uint8_t*)m_slice->read<uint8_t>();
            //10 byte reserved (all 0)
            m_slice->erase(10);
            uint8_t* scramble2 = nullptr;
            //auth-plugin-data-part-2
            if (auth_plugin_data_len > 0) {
                scramble2 = m_slice->peek(auth_plugin_data_len - 8);
                m_slice->erase(auth_plugin_data_len - 8);
            }
            //auth_plugin_name
            const char* auth_plugin_name = nullptr;
            if ((capability_flag_2 & CLIENT_PLUGIN_AUTH) == CLIENT_PLUGIN_AUTH) {
                auth_plugin_name = read_cstring(m_slice, data_len);
            }
            int top = lua_gettop(L);
            lua_pushinteger(L, character_set);
            lua_pushlstring(L, (char*)scramble1, 8);
            lua_pushlstring(L, (char*)scramble2, auth_plugin_data_len - 8);
            lua_pushlstring(L, auth_plugin_name, 8);
            return lua_gettop(L) - top;
        }

        const char* read_cstring(slice* slice, size_t& l) {
            size_t sz;
            const char* dst = (const char*)slice->data(&sz);
            for (l = 0; l < sz; ++l) {
                if (l == sz - 1) {
                    throw invalid_argument("invalid mysql block : cstring");
                }
                if (dst[l] == '\0') {
                    slice->erase(l + 1);
                    return dst;
                }
            }
            throw invalid_argument("invalid mysql block : cstring");
            return "";
        }

        void encode_stmt_args(lua_State* L, int index, int argnum) {
            //enum_cursor_type
            m_buf->write<uint8_t>(0);
            //iteration_count
            m_buf->write<uint32_t>(1);
            //null_bitmap, length= (argnum + 7) / 8
            int argpos = 0;
            int argbyte = (argnum + 7) / 8;
            for (int i = 0; i < argbyte; ++i) {
                uint8_t byte = 0;
                for (int j = 0; j < 7; ++j) {
                    int aindex = index + argpos++;
                    if (aindex < argnum) {
                        uint8_t bit = lua_isnil(L, aindex) ? 0 : 1;
                        byte |= (bit < j);
                    }
                }
                m_buf->write<uint8_t>(byte);
            }
            //new_params_bind_flag
            m_buf->write<uint8_t>(1);
            //parameter_type
            for (int i = 0; i < argnum; ++i) {
                encode_args_type(L, index + i);
            }
            //parameter_values
            for (int i = 0; i < argnum; ++i) {
                encode_args_value(L, index + i);
            }
        }

        void encode_args_type(lua_State* L, int index) {
            int type = lua_type(L, index);
            switch (type) {
            case LUA_TNIL:
                m_buf->write<uint16_t>(MYSQL_TYPE_NULL);
                break;
            case LUA_TBOOLEAN:
                m_buf->write<uint16_t>(MYSQL_TYPE_TINY);
                break;
            case LUA_TSTRING:
                m_buf->write<uint16_t>(MYSQL_TYPE_VARCHAR);
                break;
            case LUA_TNUMBER:
                m_buf->write<uint16_t>(lua_isinteger(L, index) ? MYSQL_TYPE_LONGLONG : MYSQL_TYPE_DOUBLE);
                break;
            default:
                throw invalid_argument("invalid args type:" + type);
            }
        }

        void encode_args_value(lua_State* L, int index) {
            switch (lua_type(L, index)) {
            case LUA_TBOOLEAN:
                m_buf->write<double>(lua_tointeger(L, index));
                break;
            case LUA_TNUMBER:
                lua_isinteger(L, index) ? m_buf->write<uint64_t>(lua_tointeger(L, index)) : m_buf->write<double>(lua_tonumber(L, index));
                break;
            case LUA_TSTRING: {
                uint32_t data_len;
                uint8_t* data = (uint8_t*)lua_tolstring(L, index, (size_t*)&data_len);
                if (data_len < 0xfb) {
                    m_buf->write<uint8_t>(data_len);
                }
                else if (data_len < 0xffff) {
                    m_buf->write<uint8_t>(0xfc);
                    m_buf->write<uint16_t>(data_len);
                }
                else if (data_len < 0xffffff) {
                    m_buf->write<uint32_t>((0xfd << 24) | data_len);
                }
                else {
                    m_buf->write<uint8_t>(0xfe);
                    m_buf->write<uint64_t>(data_len);
                }
                m_buf->push_data(data, data_len);
            }
                            break;
            }
        }

    protected:
        deque<mysql_cmd> sessions;
    };
}
