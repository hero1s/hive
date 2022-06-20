#pragma once
#ifdef WIN32
#pragma warning(disable: 4244)
#pragma warning(disable: 4267)
#endif

#include <vector>
#include "buffer.h"

namespace lbuffer {
    const uint8_t type_nil          = 0;
    const uint8_t type_true         = 1;
    const uint8_t type_false        = 2;
    const uint8_t type_tab_head     = 3;
    const uint8_t type_tab_tail     = 4;
    const uint8_t type_number       = 5;
    const uint8_t type_int16        = 6;
    const uint8_t type_int32        = 7;
    const uint8_t type_int64        = 8;
    const uint8_t type_str_shrt     = 9;
    const uint8_t type_str_long     = 10;
    const uint8_t type_index        = 11;
    const uint8_t type_max          = 12;

    const uint8_t max_encode_depth  = 16;
    const uint8_t max_share_string  = 255;
    const uint8_t max_uint8         = UCHAR_MAX - type_max;

    class serializer {
    public:
        serializer() {
            m_buffer = new var_buffer();
        }

        ~serializer() {
            delete m_buffer;
        }
        
        slice* encode(lua_State* L) {
            m_buffer->reset();
            m_sshares.clear();
            int n = lua_gettop(L);
            for (int i = 1; i <= n; i++) {
                encode_one(L, i, 0);
            }
            return m_buffer->get_slice();
        }

        int encode_string(lua_State* L) {
            size_t data_len = 0;
            slice* buf = encode(L);
            const char* data = (const char*)buf->data(&data_len);
            lua_pushlstring(L, data, data_len);
            lua_pushinteger(L, data_len);
            return 2;
        }

        int decode(lua_State* L, slice* buf){
            m_sshares.clear();
            lua_settop(L, 0);
            while (1) {
                uint8_t type;
                if (buf->pop(&type, sizeof(uint8_t)) == 0)
                    break;
                decode_value(L, buf, type);
            }
            return lua_gettop(L);
        }

        int decode_string(lua_State* L, const char* buf, size_t len) {
            m_buffer->reset();
            m_buffer->push_data((uint8_t*)buf, len);
            return decode(L, m_buffer->get_slice());
        }

        int serialize(lua_State* L) {
            m_buffer->reset();
            size_t data_len = 0;
            serialize_one(L, 1, 1, luaL_optinteger(L, 2, 0));
            const char* data = (const char*)m_buffer->data(&data_len);
            lua_pushlstring(L, data, data_len);
            return 1;
        }

        int unserialize(lua_State* L) {
            size_t data_len = 0;
            std::string temp = "return ";
            auto data = luaL_checklstring(L, 1, &data_len);
            temp.append(data, data_len);
            if (luaL_loadbufferx(L, temp.c_str(), temp.size(), "unserialize", "bt") == 0) {
                if (lua_pcall(L, 0, 1, 0) == 0) {
                    return 1;
                }
            }
            return luaL_error(L, lua_tostring(L, -1));
        }

    protected:
        int16_t find_index(std::string str) {
            for (int i = 0; i < m_sshares.size(); ++i) {
                if (m_sshares[i] == str) {
                    return i;
                }
            }
            return -1;
        }

        std::string find_string(size_t index) {
            if (index < m_sshares.size()) {
                return m_sshares[index];
            }
            return "";
        }

        void string_encode(lua_State* L, int index) {
            size_t sz = 0;
            const char* ptr = lua_tolstring(L, index, &sz);
            if (sz > USHRT_MAX) {
                luaL_error(L, "encode can't pack too long string");
                return;
            }
            std::string value(ptr, sz);
            int16_t sindex = find_index(value);
            if (sindex < 0){
                if (sz > UCHAR_MAX) {
                    value_encode(type_str_long);
                    value_encode<uint16_t>(sz);
                }
                else {
                    value_encode(type_str_shrt);
                    value_encode<uint8_t>(sz);
                }
                if (sz > 0) {
                    value_encode(ptr, sz);
                    if (m_sshares.size() < max_share_string) {
                        m_sshares.push_back(value);
                    }
                }
                return;
            }
            value_encode(type_index);
            value_encode<uint8_t>(sindex);
        }

        void integer_encode(int64_t integer) {
            if (integer >= 0 && integer <= max_uint8) {
                integer += type_max;
                value_encode<uint8_t>(integer);
                return;
            }
            if (integer <= SHRT_MAX && integer >= SHRT_MIN) {
                value_encode(type_int16);
                value_encode<int16_t>(integer);
                return;
            }
            if (integer <= INT_MAX && integer >= INT_MIN) {
                value_encode(type_int32);
                value_encode<int32_t>(integer);
                return;
            }
            value_encode(type_int64);
            value_encode(integer);
        }
        
        void number_encode(double number) {
            value_encode(type_number);
            value_encode(number);
        }

        void encode_one(lua_State* L, int idx, int depth) {
            if (depth > max_encode_depth) {
                luaL_error(L, "encode can't pack too depth table");
            }
            int type = lua_type(L, idx);
            switch (type) {
            case LUA_TNIL:
                value_encode(type_nil);
                break;
            case LUA_TSTRING:
                string_encode(L, idx);
                break;
            case LUA_TTABLE: 
                table_encode(L, idx, depth + 1);
                break;
            case LUA_TBOOLEAN:
                lua_toboolean(L, idx) ? value_encode(type_true) : value_encode(type_false);
                break;
            case LUA_TNUMBER: 
                lua_isinteger(L, idx) ? integer_encode(lua_tointeger(L, idx)) : number_encode(lua_tonumber(L, idx));
                break;
            default:
                break;
            }
        }
        
        void table_encode(lua_State* L, int index, int depth) {
            index = lua_absindex(L, index);
            value_encode(type_tab_head);
            lua_pushnil(L);
            while (lua_next(L, index) != 0) {
                encode_one(L, -2, depth);
                encode_one(L, -1, depth);
                lua_pop(L, 1);
            }
            value_encode(type_tab_tail);
        }

        void string_decode(lua_State* L, slice* buf, uint16_t sz) {
            if (sz == 0) {
                lua_pushstring(L, "");
                return;
            }
            auto str = (const char*)buf->peek(sz);
            if (str == nullptr) {
                luaL_error(L, "decode string is out of range");
                return;
            }
            buf->erase(sz);
            m_sshares.push_back(std::string(str, sz));
            lua_pushlstring(L, str, sz);
        }

        void index_decode(lua_State* L, slice* buf) {
            uint8_t index = value_decode<uint8_t>(L, buf);
            std::string str = find_string(index);
            lua_pushlstring(L, str.c_str(), str.size());
        }

        void table_decode(lua_State* L, slice* buf) {
            lua_newtable(L);
            do {
                if (decode_one(L, buf) == type_tab_tail) {
                    break;
                }
                decode_one(L, buf);
                lua_rawset(L, -3);
            } while (1);
        }
        
        void decode_value(lua_State* L, slice* buf, uint8_t type) {
            switch (type) {
            case type_nil:
                lua_pushnil(L);
                break;
            case type_true:
                lua_pushboolean(L, true);
                break;
            case type_false:
                lua_pushboolean(L, false);
                break;
            case type_number:
                lua_pushnumber(L, value_decode<double>(L, buf));
                break;
            case type_str_shrt:
                string_decode(L, buf, value_decode<uint8_t>(L, buf));
                break;
            case type_str_long:
                string_decode(L, buf, value_decode<uint16_t>(L, buf));
                break;
            case type_index:
                index_decode(L, buf);
                break;
            case type_tab_head:
                table_decode(L, buf);
                break;
            case type_tab_tail:
                break;
            case type_int16:
                lua_pushinteger(L, value_decode<int16_t>(L, buf));
                break;
            case type_int32:
                lua_pushinteger(L, value_decode<int32_t>(L, buf));
                break;
            case type_int64:
                lua_pushinteger(L, value_decode<int64_t>(L, buf));
                break;
            default:
                lua_pushinteger(L, type - type_max);
                break;
            }
        }

        int decode_one(lua_State* L, slice* buf) {
            uint8_t type = value_decode<uint8_t>(L, buf);
            decode_value(L, buf, type);
            return type;
        }

        template<typename T>
        void value_encode(T data) {
            m_buffer->push_data((const uint8_t*)&data, sizeof(T));
        }

        void value_encode(const char* data, size_t len) {
            m_buffer->push_data((const uint8_t*)data, len);
        }

        template<typename T>
        T value_decode(lua_State* L, slice* buff) {
            T value = 0;
            if (buff->pop((uint8_t*)&value, sizeof(T)) == 0){
                luaL_error(L, "decode can't unpack one value");
            }
            return value;
        }

        inline void serialize_value(const char* str) {
            m_buffer->push_data((const uint8_t*)str, strlen(str));
        }

        inline void serialize_udata(const char* data) {
            serialize_quote(data ? data : "userdata(null)", "'", "'");
        }

        void serialize_crcn(int count, int line) {
            if (line > 0) {
                serialize_value("\n");
                for (int i = 0; i < count; ++i) {
                    serialize_value("\t");
                }
            }
        }

        void serialize_string(lua_State* L, int index) {
            size_t sz;
            serialize_value("'");
            const char* str = luaL_checklstring(L, index, &sz);
            if (sz > 0) {
                m_buffer->push_data((const uint8_t*)str, sz);
            }
            serialize_value("'");
        }

        void serialize_quote(const char* str, const char* l, const char* r) {
            serialize_value(l);
            serialize_value(str);
            serialize_value(r);
        }

        void serialize_one(lua_State* L, int index, int depth, int line) {
            if (depth > max_encode_depth) {
                luaL_error(L, "serialize can't pack too depth table");
            }
            int type = lua_type(L, index);
            switch (type) {
            case LUA_TNIL:
                serialize_value("nil");
                break;
            case LUA_TBOOLEAN:
                serialize_value(lua_toboolean(L, index) ? "true" : "false");
                break;
            case LUA_TSTRING:
                serialize_string(L, index);
                break;
            case LUA_TNUMBER:
                serialize_value(lua_tostring(L, index));
                break;
            case LUA_TTABLE:
                serialize_table(L, index, depth + 1, line);
                break;
            case LUA_TUSERDATA:
            case LUA_TLIGHTUSERDATA:
                serialize_udata(lua_tostring(L, index));
                break;
            default:
                serialize_quote(lua_typename(L, type), "'unsupport(", ")'");
                break;
            }
        }

        void serialize_table(lua_State* L, int index, int depth, int line) {
            index = lua_absindex(L, index);
            int size = 0;
            lua_pushnil(L);
            serialize_value("{");
            serialize_crcn(depth, line);
            while (lua_next(L, index) != 0) {
                if (size++ > 0) {
                    serialize_value(",");
                    serialize_crcn(depth, line);
                }
                if (lua_isnumber(L, -2)) {
                    lua_pushvalue(L, -2);
                    serialize_quote(lua_tostring(L, -1), "[", "]=");
                    lua_pop(L, 1);
                }
                else if (lua_type(L, -2) == LUA_TSTRING) {
                    serialize_value(lua_tostring(L, -2));
                    serialize_value("=");
                }
                else {
                    serialize_one(L, -2, depth, line);
                    serialize_value("=");
                }
                serialize_one(L, -1, depth, line);
                lua_pop(L, 1);
            }
            serialize_crcn(depth - 1, line);
            serialize_value("}");
        }
    
    public:
        var_buffer* m_buffer;
        std::vector<std::string> m_sshares;
    };
}
