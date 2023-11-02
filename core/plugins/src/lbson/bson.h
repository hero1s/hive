#pragma once

#include "lua_kit.h"

using namespace std;
using namespace luakit;

//https://bsonspec.org/spec.html
namespace lbson {
    const uint8_t max_bson_depth    = 64;
    const uint32_t max_bson_index   = 1024;

    const uint32_t OP_MSG_CODE      = 2013;
    const uint32_t OP_MSG_HLEN      = 4 * 5 + 1;
    const uint32_t OP_CHECKSUM      = 1 << 0;
    const uint32_t OP_MORE_COME     = 1 << 1;

    static char bson_numstrs[max_bson_index][4];
    static int bson_numstr_len[max_bson_index];

    enum class bson_type : uint8_t {
        BSON_EOO        = 0,
        BSON_REAL       = 1,
        BSON_STRING     = 2,
        BSON_DOCUMENT   = 3,
        BSON_ARRAY      = 4,
        BSON_BINARY     = 5,
        BSON_UNDEFINED  = 6,    //Deprecated
        BSON_OBJECTID   = 7,
        BSON_BOOLEAN    = 8,
        BSON_DATE       = 9,
        BSON_NULL       = 10,
        BSON_REGEX      = 11,
        BSON_DBPOINTER  = 12,   //Deprecated
        BSON_JSCODE     = 13,
        BSON_SYMBOL     = 14,   //Deprecated
        BSON_CODEWS     = 15,   //Deprecated
        BSON_INT32      = 16,
        BSON_TIMESTAMP  = 17,   //special timestamp type only for internal MongoDB use
        BSON_INT64      = 18,
        BSON_INT128     = 19,
        BSON_MINKEY     = 255,
        BSON_MAXKEY     = 127,
    };

    class bson_value {
    public:
        int64_t val = 0;
        string str = "";
        string opt = "";
        uint8_t stype = 0;
        bson_type type = bson_type::BSON_EOO;
        bson_value(bson_type t, string s, uint8_t st = 0) : str(s), stype(st), type(t) {}
        bson_value(bson_type t, int64_t i, uint8_t st = 0) : val(i), stype(st), type(t) {}
        bson_value(bson_type t, string s, string o, uint8_t st = 0) : str(s), opt(s), stype(st), type(t) {}
        bson_value(bson_type t, const char* p, size_t l, uint8_t st = 0) : str(p, l), stype(st), type(t) {}
    };
    class mgocodec;
    class bson {
    public:
        friend mgocodec;
        slice* encode_slice(lua_State* L) {
            m_buffer.clean();
            pack_dict(L, 0);
            return m_buffer.get_slice();
        }

        int encode(lua_State* L) {
            size_t data_len = 0;
            slice* slice = encode_slice(L);
            const char* data = (const char*)slice->data(&data_len);
            lua_pushlstring(L, data, data_len);
            return 1;
        }

        int decode(lua_State* L) {
            m_buffer.clean();
            size_t data_len = 0;
            const char* buf = lua_tolstring(L, 1, &data_len);
            m_buffer.push_data((uint8_t*)buf, data_len);
            return decode_slice(L, m_buffer.get_slice());
        }

        int decode_slice(lua_State* L, slice* slice) {
            lua_settop(L, 0);
            try {
                unpack_dict(L, slice, false);
            } catch (const exception& e){
                luaL_error(L, e.what());
            }
            return lua_gettop(L);
        }

        int pairs(lua_State* L) {
            m_buffer.clean();
            size_t data_len = 0;
            bson_value* value = lua_to_object<bson_value*>(L, -1);
            if (value == nullptr) {
                char* data = (char*)encode_pairs(L, &data_len);
                value = new bson_value(bson_type::BSON_DOCUMENT, data, data_len);
            } else {
                lua_pop(L, 1);
                char* data = (char*)encode_pairs(L, &data_len);
                value->str = string(data, data_len);
            }
            lua_push_object(L, value);
            return 1;
        }

        uint8_t* encode_pairs(lua_State* L, size_t* data_len) {
            int n = lua_gettop(L);
            if (n < 2 || n % 2 != 0) {
                luaL_error(L, "Invalid ordered dict");
            }
            size_t sz;
            size_t offset = m_buffer.size();
            m_buffer.write<uint32_t>(0);
            for (int i = 0; i < n; i += 2) {
                int vt = lua_type(L, i + 2);
                if (vt != LUA_TNIL && vt != LUA_TNONE) {
                    const char* key = lua_tolstring(L, i + 1, &sz);
                    if (key == nullptr) {
                        luaL_error(L, "Argument %d need a string", i + 1);
                    }
                    lua_pushvalue(L, i + 2);
                    pack_one(L, key, sz, 0);
                    lua_pop(L, 1);
                }
            }
            m_buffer.write<uint8_t>(0);
            uint32_t size = m_buffer.size() - offset;
            m_buffer.copy(offset, (uint8_t*)&size, sizeof(uint32_t));
            //返回结果
            return m_buffer.data(data_len);
        }

        luabuf* get_buffer() {
            return &m_buffer;;
        }

    protected:
        size_t bson_index(char* str, size_t i) {
            if (i < max_bson_index) {
                memcpy(str, bson_numstrs[i], 4);
                return bson_numstr_len[i];
            }
            return sprintf(str, "%zd", i);
        }

        void write_binary(bson_value* value) {
            m_buffer.write<uint32_t>(value->str.size() + 1);
            m_buffer.write<uint8_t>(value->stype);
            m_buffer.write(value->str);
        }

        void write_cstring(const char* buf, size_t len) {
            m_buffer.push_data((uint8_t*)buf, len);
            m_buffer.write<char>('\0');
        }

        void write_string(const char* buf, size_t len) {
            m_buffer.write<uint32_t>(len + 1);
            write_cstring(buf, len);
        }

        void write_key(bson_type type, const char* key, size_t len) {
            m_buffer.write<uint8_t>((uint8_t)type);
            write_cstring(key, len);
        }

        template<typename T>
        void write_pair(bson_type type, const char* key, size_t len, T value) {
            write_key(type, key, len);
            m_buffer.write(value);
        }

        template<typename T>
        T read_val(lua_State* L, slice* slice) {
            T* value = slice->read<T>();
            if (value == nullptr) {
                luaL_error(L, "decode can't unpack one value");
            }
            return *value;
        }

        void write_number(lua_State *L, const char* key, size_t len) {
            if (lua_isinteger(L, -1)) {
                int64_t v = lua_tointeger(L, -1);
                if (v >= INT32_MIN && v <= INT32_MAX) {
                    write_pair<int32_t>(bson_type::BSON_INT32, key, len, v);
                } else {
                    write_pair<int64_t>(bson_type::BSON_INT64, key, len, v);
                }
            } else {
                write_pair<double>(bson_type::BSON_REAL, key, len, lua_tonumber(L, -1));
            }
        }

        void pack_array(lua_State *L, int depth, size_t len) {
            // length占位
            char numkey[32];
            size_t offset = m_buffer.size();
            m_buffer.write<uint32_t>(0);
            for (size_t i = 1; i <= len; i++) {
                lua_geti(L, -1, i);
                size_t len = bson_index(numkey, i - 1);
                pack_one(L, numkey, len, depth);
                lua_pop(L, 1);
            }
            m_buffer.write<uint8_t>(0);
            uint32_t size = m_buffer.size() - offset;
            m_buffer.copy(offset, (uint8_t*)&size, sizeof(uint32_t));
        }

        bson_type check_doctype(lua_State *L, size_t raw_len) {
            if (raw_len == 0) return bson_type::BSON_DOCUMENT;
            lua_guard g(L);
            lua_pushnil(L);
            size_t cur_len = 0;
            while(lua_next(L, -2) != 0) {
                if (!lua_isinteger(L, -2)) {
                    return bson_type::BSON_DOCUMENT;
                }
                size_t key = lua_tointeger(L, -2);
                if (key <= 0 || key > raw_len) {
                    return bson_type::BSON_DOCUMENT;
                }
                cur_len++;
                lua_pop(L, 1);
            }
            return cur_len == raw_len ? bson_type::BSON_ARRAY : bson_type::BSON_DOCUMENT;
        }

        void pack_table(lua_State *L, const char* key, size_t len, int depth) {
            if (depth > max_bson_depth) {
                luaL_error(L, "Too depth while encoding bson");
            }
            size_t raw_len = lua_rawlen(L, -1);
            bson_type type = check_doctype(L, raw_len);
            write_key(type, key, len);
            if (type == bson_type::BSON_DOCUMENT) {
                pack_dict(L, depth);
            } else {
                pack_array(L, depth, raw_len);
            }
        }

        void pack_bson_value(lua_State* L, bson_value* value){
            switch(value->type) {
            case bson_type::BSON_MINKEY:
            case bson_type::BSON_MAXKEY:
            case bson_type::BSON_NULL:
                break;
            case bson_type::BSON_BINARY:
                write_binary(value);
                break;
            case bson_type::BSON_INT32:
                m_buffer.write<int32_t>(value->val);
                break;
            case bson_type::BSON_DATE:
            case bson_type::BSON_INT64:
            case bson_type::BSON_TIMESTAMP:
                m_buffer.write<int64_t>(value->val);
                break;
            case bson_type::BSON_ARRAY:
            case bson_type::BSON_JSCODE:
            case bson_type::BSON_DOCUMENT:
            case bson_type::BSON_OBJECTID:
                m_buffer.write(value->str);
                break;
            case bson_type::BSON_REGEX:
                write_cstring(value->str.c_str(), value->str.size());
                write_cstring(value->opt.c_str(), value->opt.size());
                break;
            default:
                luaL_error(L, "Invalid value type : %d", (int)value->type);
            }
        }

        void pack_one(lua_State *L, const char* key, size_t len, int depth) {
            int vt = lua_type(L, -1);
            switch(vt) {
            case LUA_TNUMBER:
                write_number(L, key, len);
                break;
            case LUA_TBOOLEAN:
                write_pair<bool>(bson_type::BSON_BOOLEAN, key, len, lua_toboolean(L, -1));
                break;
            case LUA_TTABLE:{
                    bson_value* value = lua_to_object<bson_value*>(L, -1);
                    if (value){
                        write_key(value->type, key, len);
                        pack_bson_value(L, value);
                    } else {
                        pack_table(L, key, len, depth + 1);
                    }
                }
                break;
            case LUA_TSTRING: {
                    size_t sz;
                    const char* buf = lua_tolstring(L, -1, &sz);
                    write_key(bson_type::BSON_STRING, key, len);
                    write_string(buf, sz);
                }
                break;
            case LUA_TNIL:
                luaL_error(L, "Bson array has a hole (nil), Use bson.null instead");
                break;
            default:
                luaL_error(L, "Invalid value type : %s", lua_typename(L,vt));
            }
        }

        void pack_dict_data(lua_State *L, int depth, int kt) {
            if (kt == LUA_TSTRING) {
                size_t sz;
                const char* buf = lua_tolstring(L, -2, &sz);
                pack_one(L, buf, sz, depth);
                return;
            }
            if (lua_isinteger(L, -2)){
                char numkey[32];
                size_t len = bson_index(numkey, lua_tointeger(L, -2));
                pack_one(L, numkey, len, depth);
                return;
            }
            luaL_error(L, "Invalid key type : %s", lua_typename(L, kt));
        }

        void pack_dict(lua_State *L, int depth) {
            // length占位
            size_t offset = m_buffer.size();
            m_buffer.write<uint32_t>(0);
            lua_pushnil(L);
            while(lua_next(L, -2) != 0) {
                pack_dict_data(L, depth, lua_type(L, -2));
                lua_pop(L, 1);
            }
            m_buffer.write<uint8_t>(0);
            uint32_t size = m_buffer.size() - offset;
            m_buffer.copy(offset, (uint8_t*)&size, sizeof(uint32_t));
        }

        const char* read_bytes(lua_State* L, slice* slice, size_t sz) {
            const char* dst = (const char*)slice->peek(sz);
            if (!dst) {
                throw invalid_argument("invalid bson string , length = " + sz);
            }
            slice->erase(sz);
            return dst;
        }

        const char* read_string(lua_State* L, slice* slice, size_t& sz) {
            sz = (size_t)read_val<uint32_t>(L, slice);
            if (sz <= 0) {
                throw invalid_argument("invalid bson string , length = " + sz);
            }
            sz = sz - 1;
            const char* dst = "";
            if (sz > 0) {
                dst = read_bytes(L, slice, sz);
            }
            slice->erase(1);
            return dst;
        }

        const char* read_cstring(slice* slice, size_t& l) {
            size_t sz;
            const char* dst = (const char*)slice->data(&sz);
            for (l = 0; l < sz; ++l) {
                if (dst[l] == '\0') {
                    slice->erase(l + 1);
                    return dst;
                }
                if (l == sz - 1) {
                    throw invalid_argument("invalid bson block : cstring");
                }
            }
            throw invalid_argument("invalid bson block : cstring");
            return "";
        }

        void unpack_key(lua_State* L, slice* slice, bool isarray) {
            size_t klen = 0;
            const char* key = read_cstring(slice, klen);
            if (isarray) {
                lua_pushinteger(L, std::stoll(key, nullptr, 10) + 1);
                return;
            }
            if (lua_stringtonumber(L, key) == 0) {
                lua_pushlstring(L, key, klen);
            }
        }

        void unpack_dict(lua_State* L, slice* slice, bool isarray) {
            uint32_t sz = read_val<uint32_t>(L, slice);
            if (slice->size() < sz - 4) {
                throw invalid_argument("decode can't unpack one value");
            }
            lua_createtable(L, 0, 8);
            while (!slice->empty()) {
                size_t klen = 0;
                bson_type bt = (bson_type)read_val<uint8_t>(L, slice);
                if (bt == bson_type::BSON_EOO) break;
                unpack_key(L, slice, isarray);
                switch (bt) {
                case bson_type::BSON_REAL:
                    lua_pushnumber(L, read_val<double>(L, slice));
                    break;
                case bson_type::BSON_BOOLEAN:
                    lua_pushboolean(L, read_val<bool>(L, slice));
                    break;
                case bson_type::BSON_INT32:
                    lua_pushinteger(L, read_val<int32_t>(L, slice));
                    break;
                case bson_type::BSON_DATE:
                case bson_type::BSON_INT64:
                case bson_type::BSON_TIMESTAMP:
                    lua_pushinteger(L, read_val<int64_t>(L, slice));
                    break;
                case bson_type::BSON_OBJECTID:{
                        const char* s = read_bytes(L, slice, 12);
                        lua_pushlstring(L, s, 12);
                    }
                    break;
                case bson_type::BSON_JSCODE:
                case bson_type::BSON_STRING:{
                        const char* s = read_string(L, slice, klen);
                        lua_pushlstring(L, s, klen);
                    }
                    break;
                case bson_type::BSON_BINARY: {
                        uint32_t sz = read_val<uint32_t>(L, slice);
                        uint8_t subtype = read_val<uint8_t>(L, slice);
                        const char* s = read_bytes(L, slice, sz);
                        lua_pushlstring(L, s, sz);
                    }
                    break;
                case bson_type::BSON_REGEX:
                    lua_push_object(L, new bson_value(bt, read_cstring(slice, klen), read_cstring(slice, klen)));
                    break;
                case bson_type::BSON_DOCUMENT:
                    unpack_dict(L, slice, false);
                    break;
                case bson_type::BSON_ARRAY:
                    unpack_dict(L, slice, true);
                    break;
                case bson_type::BSON_MINKEY:
                case bson_type::BSON_MAXKEY:
                case bson_type::BSON_NULL:
                    lua_push_object(L, new bson_value(bt, 0));
                    break;
                default:
                    throw invalid_argument("invalid bson type:" + (int)bt);
                }
                lua_rawset(L, -3);
            }
        }
    private:
        luabuf m_buffer;
    };

    class mgocodec : public codec_base {
    public:
        virtual int load_packet(size_t data_len) {
            if (!m_slice) return 0;
            uint32_t* packet_len = (uint32_t*)m_slice->peek(sizeof(uint32_t));
            if (!packet_len) return 0;
            m_packet_len = *packet_len;
            if (m_packet_len > 0xffffff) return -1;
            if (m_packet_len > data_len) return 0;
            if (!m_slice->peek(m_packet_len)) return 0;
            return m_packet_len;
        }

        virtual uint8_t* encode(lua_State* L, int index, size_t* len) {
            luabuf* buf = m_bson->get_buffer();
            buf->clean();
            buf->write<uint32_t>(0);
            buf->write<uint32_t>(lua_tointeger(L, 1));
            buf->write<uint32_t>(0);
            buf->write<uint32_t>(OP_MSG_CODE);
            buf->write<uint32_t>(0);
            buf->write<uint8_t>(0);
            lua_remove(L, 1);
            uint8_t* data = m_bson->encode_pairs(L, len);
            buf->copy(0, (uint8_t*)len, sizeof(uint32_t));
            return data;
        }

        virtual size_t decode(lua_State* L) {
            if (!m_slice) return 0;
            //skip length + request_id
            m_slice->erase(8);
            uint32_t session_id = m_bson->read_val<uint32_t>(L, m_slice);
            uint32_t opcode = m_bson->read_val<uint32_t>(L, m_slice);
            if (opcode != OP_MSG_CODE) {
                throw invalid_argument("unsupported opcode:" + opcode);
            }
            uint32_t flags = m_bson->read_val<uint32_t>(L, m_slice);
            if (flags > 0 && ((flags & OP_CHECKSUM) != 0 || ((flags ^ OP_MORE_COME) != 0))) {
                throw invalid_argument("unsupported flags:" + flags);
            }
            uint32_t payload = m_bson->read_val<uint8_t>(L, m_slice);
            if (payload != 0) {
                throw invalid_argument("unsupported payload:" + payload);
            }
            int otop = lua_gettop(L);
            lua_pushinteger(L, session_id);
            try {
                m_bson->unpack_dict(L, m_slice, false);
            } catch (const exception& e){
                lua_settop(L, otop);
                throw e;
            }
            return lua_gettop(L) - otop;
        }

        void set_bson(bson* bson) {
            m_bson = bson;
        }

    protected:
        bson* m_bson;
    };
}