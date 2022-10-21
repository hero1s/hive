#pragma once

namespace lcodec {
    static int hash_code(lua_State* L) {
        size_t hcode = 0;
        int type = lua_type(L, 1);
        if (type == LUA_TNUMBER) {
            hcode = std::hash<int64_t>{}(lua_tointeger(L, 1));
        } else if (type == LUA_TSTRING) {
            hcode = std::hash<std::string>{}(lua_tostring(L, 1));
        } else {
            luaL_error(L, "hashkey only support number or string!");
        }
        size_t mod = luaL_optinteger(L, 2, 0);
        if (mod > 0) {
            hcode = (hcode % mod) + 1;
        }
        lua_pushinteger(L, hcode);
        return 1;
    }

    static int fnv_32(lua_State* L) {
        size_t len;
        unsigned char* bp = (unsigned char*)lua_tolstring(L, 1, &len);
        uint32_t hval = luaL_optinteger(L, 2, 0);
        while (*bp) {
            hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) + (hval << 24);
            hval ^= (uint32_t)*bp++;
        }
        lua_pushinteger(L, hval);
        return 1;
    }

    static int fnv_32a(lua_State* L) {
        size_t len;
        unsigned char* bp = (unsigned char*)lua_tolstring(L, 1, &len);
        unsigned char *be = bp + len;
        uint32_t hval = luaL_optinteger(L, 2, 0);
        while (bp < be) {
            hval ^= (uint32_t)*bp++;
            hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) + (hval << 24);
        }
        lua_pushinteger(L, hval);
        return 1;
    }
}
