#include "lrucache.hpp"
#include "lua_kit.h"
#include <vector>
#include <memory>

namespace cache {
    using cache_type = cache::lru_cache<std::string, std::string>;

	static int lput(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		auto key = luakit::lua_to_native<std::string>(L, 2);
		size_t data_len;
		char* data = (char*)luakit::create_codec()->encode(L, 3, &data_len);
		if (data) {
			cache->put(key, std::string(data, data_len));
		} else {
			return luaL_argerror(L, 3, "not data prama");
		}
		return 0;
	}

	static int lget(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		auto key = luakit::lua_to_native<std::string>(L, 2);
		try
		{
			auto value = cache->get(key);
			luakit::create_codec()->decode(L,(uint8_t*)value.c_str(),value.size());
		}
		catch (const std::exception&)
		{
			lua_pushnil(L);
		}
		return 1;
	}

	static int ldel(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		auto key = luakit::lua_to_native<std::string>(L, 2);
		lua_pushboolean(L, cache->remove(key) ? 1 : 0);
		return 1;
	}

	static int lexist(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		auto key = luakit::lua_to_native<std::string>(L, 2);
		lua_pushboolean(L, cache->exist(key) ? 1 : 0);
		return 1;
	}

	static int lsize(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		lua_pushinteger(L, cache->size());
		return 1;
	}

	static int lrelease(lua_State* L) {
		cache_type* cache = (cache_type*)lua_touserdata(L, 1);
		if (nullptr == cache) {
			return luaL_argerror(L, 1, "invalid lua-cache pointer");
		}
		std::destroy_at(cache);
		return 0;
	}

    static int lcreate(lua_State* L) {
        size_t max_count = (size_t)luaL_checkinteger(L, 1);
		if (max_count < 1) {
			return luaL_argerror(L, 1, "cache size < 1");
		}
		void* p = lua_newuserdatauv(L, sizeof(cache_type), 0);
		new (p) cache_type(max_count);
		if (luaL_newmetatable(L, "lcache"))//mt
		{
			luaL_Reg l[] = {
				{ "put", lput},
				{ "get", lget},
				{ "del", ldel},
				{ "exist", lexist},				
				{ "size", lsize},				
				{ NULL,NULL }
			};
			luaL_newlib(L, l); //{}
			lua_setfield(L, -2, "__index");//mt[__index] = {}
			lua_pushcfunction(L, lrelease);
			lua_setfield(L, -2, "__gc");//mt[__gc] = lrelease
		}
		lua_setmetatable(L, -2);// set userdata metatable
		return 1;
    }
}

extern "C" {
    LUALIB_API int luaopen_lcache(lua_State* L)
	{
		luaL_Reg l[] = {
			{"new",cache::lcreate},
			{"release",cache::lrelease},
			{NULL,NULL}
		};
		luaL_newlib(L, l);
		return 1;
    }
}
