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

    static uint32_t fnv_1_32(const char* bp, uint32_t hval) {
        unsigned char* be = (unsigned char*)bp;
        while (*bp) {
            hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) + (hval << 24);
            hval ^= (uint32_t)*bp++;
        }
        return hval;
    }

    static int fnv_1_32_l(lua_State* L) {
        size_t len;
        const char* bp = lua_tolstring(L, 1, &len);
        uint32_t hval = luaL_optinteger(L, 2, 0);
        lua_pushinteger(L, fnv_1_32(bp, hval));
        return 1;
    }

    static uint32_t fnv_1a_32(const char* b, size_t len, uint32_t hval) {
        unsigned char* bp = (unsigned char*)b;
        unsigned char* be = bp + len;
        while (bp < be) {
            hval ^= (uint32_t)*bp++;
            hval += (hval << 1) + (hval << 4) + (hval << 7) + (hval << 8) + (hval << 24);
        }
        return hval;
    }

    static int fnv_1a_32_l(lua_State* L) {
        size_t len;
        const char* bp = lua_tolstring(L, 1, &len);
        uint32_t hval = luaL_optinteger(L, 2, 0);
        lua_pushinteger(L, fnv_1a_32(bp, len, hval));
        return 1;
    }

    const uint32_t c1 = 0xcc9e2d51;
    const uint32_t c2 = 0x1b873593;
    inline uint32_t rotl32(uint32_t x, int8_t r) {
        return (x << r) | (x >> (32 - r));
    }

    static uint32_t murmur3_32(const uint8_t* data, size_t length) {
        uint32_t h1 = 0;
        const int nblocks = length / 4;
        // body
        const uint32_t* blocks = (const uint32_t *)(data + nblocks*4);
        for(int i = -nblocks; i; i++) {
            uint32_t k1 = blocks[i];
            k1 *= c1;
            k1 = rotl32(k1, 15);
            k1 *= c2;
            h1 ^= k1;
            h1 = rotl32(h1, 13);
            h1 = h1*5 + 0xe6546b64;
        }
        // tail
        const uint8_t * tail = (const uint8_t*)(data + nblocks*4);
        uint32_t k1 = 0;
        switch(length & 3)
        {
        case 3: k1 ^= tail[2] << 16;
        case 2: k1 ^= tail[1] << 8;
        case 1: k1 ^= tail[0];
                k1 *= c1; k1 = rotl32(k1,15); k1 *= c2; h1 ^= k1;
        };
        // finalization
        h1 ^= length;
        //fmix32
        h1 ^= h1 >> 16;
        h1 *= 0x85ebca6b;
        h1 ^= h1 >> 13;
        h1 *= 0xc2b2ae35;
        h1 ^= h1 >> 16;
        return h1;
    }

    static int murmur3_32_l(lua_State* L) {
        size_t length;
        const uint8_t * data = (const uint8_t*)lua_tolstring(L, 1, &length);
        lua_pushinteger(L, murmur3_32(data, length));
        return 1;
    }

    static int32_t jumphash(uint64_t key, int32_t num_buckets) {
        int64_t b = -1, j = 0;
        while (j < num_buckets) {
            b = j;
            key = key * 2862933555777941757ULL + 1;
            j = (b + 1) * (double(1LL << 31) / double((key >> 33) + 1));
        }
        return b;
    }

    static int jumphash_l(lua_State* L) {
        uint64_t key = 0;
        int type = lua_type(L, 1);
        if (type == LUA_TNUMBER) {
            key = lua_tointeger(L, 1);
        } else if (type == LUA_TSTRING) {
            key = fnv_1_32(lua_tostring(L, 1), 0);
        } else {
            luaL_error(L, "hashkey only support number or string!");
        }
        int32_t num_buckets = lua_tointeger(L, 2);
        int32_t hval = jumphash(key, num_buckets);
        lua_pushinteger(L, hval + 1);
        return 1;
    }
}
