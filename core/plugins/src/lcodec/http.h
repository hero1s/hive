#pragma once
#include <vector>
#include <string>
#include <string.h>

#include "lua_kit.h"

#ifdef _MSC_VER
#define strncasecmp _strnicmp
#endif

using namespace std;
using namespace luakit;

namespace lcodec {

    inline size_t       LCRLF   = 2;
    inline size_t       LCRLF2  = 4;
    inline const char*  CRLF    = "\r\n";
    inline const char*  CRLF2   = "\r\n\r\n";

    #define SC_UNKNOWN          0
    #define SC_PROTOCOL         101
    #define SC_OK               200
    #define SC_NOCONTENT        204
    #define SC_PARTIAL          206
    #define SC_OBJMOVED         302
    #define SC_BADREQUEST       400
    #define SC_FORBIDDEN        403
    #define SC_NOTFOUND         404
    #define SC_BADMETHOD        405
    #define SC_SERVERERROR      500
    #define SC_SERVERBUSY       503

    class httpcodec : public codec_base {
    public:
        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            m_buf->clean();
            //status (http begining)
            format_http(lua_tointeger(L, index));
            //headers
            lua_pushnil(L);
            while (lua_next(L, index + 1) != 0) {
                format_http_header(lua_tostring(L, -2), lua_tostring(L, -1));
                lua_pop(L, 1);
            }
            //body
            uint8_t* body = nullptr;
            if (lua_type(L, index + 2) == LUA_TTABLE) {
                body = m_jcodec->encode(L, index + 2, len);
            } else {
                body = (uint8_t*)lua_tolstring(L, index + 2, len);
            }
            format_http_header("Content-Length", std::to_string(*len));
            m_buf->push_data((const uint8_t*)CRLF, LCRLF);
            m_buf->push_data(body, *len);
            return m_buf->data(len);
        }

        virtual size_t decode(lua_State* L) {
            if (!m_slice) return 0;
            int top = lua_gettop(L);
            size_t osize = m_slice->size();
            string_view buf = m_slice->contents();
            parse_http_packet(L, buf);
            m_slice->erase(osize - buf.size());
            return lua_gettop(L) - top;
        }

        void set_codec(codec_base* codec) {
            m_jcodec = codec;
        }

        void set_buff(luabuf* buf) {
            m_buf = buf;
        }

    protected:
        void format_http(size_t status) {
            switch (status) {
            case SC_OK:         m_buf->write("HTTP/1.1 200 OK\r\n"); break;
            case SC_NOCONTENT:  m_buf->write("HTTP/1.1 204 No Content\r\n"); break;
            case SC_PARTIAL:    m_buf->write("HTTP/1.1 206 Partial Content\r\n"); break;
            case SC_BADREQUEST: m_buf->write("HTTP/1.1 400 Bad Request\r\n"); break;
            case SC_OBJMOVED:   m_buf->write("HTTP/1.1 302 Moved Temporarily\r\n"); break;
            case SC_NOTFOUND:   m_buf->write("HTTP/1.1 404 Not Found\r\n"); break;
            case SC_BADMETHOD:  m_buf->write("HTTP/1.1 405 Method Not Allowed\r\n"); break;
            case SC_PROTOCOL:   m_buf->write("HTTP/1.1 101 Switching Protocols\r\n"); break;
            default: m_buf->write("HTTP/1.1 500 Internal Server Error\r\n"); break;
            }
        }

        void format_http_header(string_view key, string_view val) {
            m_buf->push_data((uint8_t*)key.data(), key.size());
            m_buf->push_data((uint8_t*)": ", LCRLF);
            m_buf->push_data((uint8_t*)val.data(), val.size());
            m_buf->push_data((const uint8_t*)CRLF, LCRLF);
        }

        void split(string_view str, string_view delim, vector<string_view>& res) {
            size_t cur = 0;
            size_t step = delim.size();
            size_t pos = str.find(delim);
            while (pos != string_view::npos) {
                res.push_back(str.substr(cur, pos - cur));
                cur = pos + step;
                pos = str.find(delim, cur);
            }
            if (str.size() > cur) {
                res.push_back(str.substr(cur));
            }
        }

        void http_parse_url(lua_State* L, string_view url) {
            string_view sparams;
            size_t pos = url.find("?");
            if (pos != string_view::npos) {
                sparams = url.substr(pos + 1);
                url = url.substr(0, pos);
            }
            if (url.size() > 1 && url.back() == '/') {
                url.remove_suffix(1);
            }
            //url
            lua_pushlstring(L, url.data(), url.size());
            //params
            lua_createtable(L, 0, 4);
            if (!sparams.empty()) {
                vector<string_view> params;
                split(sparams, "&", params);
                for (string_view param : params) {
                    size_t pos = param.find("=");
                    if (pos != string_view::npos) {
                        string_view key = param.substr(0, pos);
                        param.remove_prefix(pos + 1);
                        lua_pushlstring(L, key.data(), key.size());
                        lua_pushlstring(L, param.data(), param.size());
                        lua_settable(L, -3);
                    }
                }
            }
        }

        void http_parse_body(lua_State* L, string_view header, string_view& buf) {
            m_buf->clean();
            bool jsonable = false;
            bool contentlenable = false;
            slice* mslice = nullptr;
            vector<string_view> headers;
            split(header, CRLF, headers);
            lua_createtable(L, 0, 4);
            for (auto header : headers) {
                size_t pos = header.find(":");
                if (pos != string_view::npos) {
                    string_view key = header.substr(0, pos);
                    header.remove_prefix(pos + 1);
                    header.remove_prefix(header.find_first_not_of(" "));
                    if (!strncasecmp(key.data(), "Content-Length", key.size())) {
                        contentlenable = true;
                        mslice = m_buf->get_slice();
                        size_t content_size = atol(header.data());
                        mslice->attach((uint8_t*)buf.data(), content_size);
                        buf.remove_prefix(content_size);
                    }
                    else if (!strncasecmp(key.data(), "Transfer-Encoding", key.size()) && !strncasecmp(header.data(), "chunked", header.size())) {
                        contentlenable = true;
                        size_t pos = buf.find(CRLF2);
                        string_view chunk_data = buf.substr(0, pos);
                        buf.remove_prefix(pos + LCRLF2);
                        vector<string_view> chunks;
                        split(chunk_data, CRLF, chunks);
                        for (size_t i = 0; i < chunks.size(); i++) {
                            if (i % 2 != 0) {
                                m_buf->push_data((const uint8_t*)chunks[i].data(), chunks[i].size());
                            }
                        }
                        mslice = m_buf->get_slice();
                    }
                    else if (!strncasecmp(key.data(), "Content-Type", key.size()) && !strncasecmp(header.data(), "application/json", strlen("application/json"))) {
                        jsonable = true;
                    }
                    //压栈
                    lua_pushlstring(L, key.data(), key.size());
                    lua_pushlstring(L, header.data(), header.size());
                    lua_settable(L, -3);
                }
            }
            if (!contentlenable) {
                mslice = m_buf->get_slice();
                mslice->attach((uint8_t*)buf.data(), buf.size());
                buf.remove_prefix(buf.size());
            }
            if (jsonable) {
                m_jcodec->set_slice(mslice);
                m_jcodec->decode(L);
                return;
            }
            lua_pushlstring(L, (char*)mslice->head(), mslice->size());
        }

        void parse_http_packet(lua_State* L, string_view& buf) {
            size_t pos = buf.find(CRLF2);
            if (pos == string_view::npos) throw length_error("http text not full");
            string_view header = buf.substr(0, pos);
            buf.remove_prefix(pos + LCRLF2);
            auto begining = read_line(header);
            vector<string_view> parts;
            split(begining, " ", parts);
            //method
            lua_pushlstring(L, parts[0].data(), parts[0].size());
            //url + params
            http_parse_url(L, parts[1]);
            //header + body
            http_parse_body(L, header, buf);
        }

        string_view read_line(string_view& buf) {
            size_t pos = buf.find(CRLF);
            auto ss = buf.substr(0, pos);
            buf.remove_prefix(pos + LCRLF);
            return ss;
        }

    protected:
        luabuf*     m_buf = nullptr;
        codec_base* m_jcodec = nullptr;
    };
}
