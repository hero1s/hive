#include <cstdint>
#include <numeric>
#include <iterator>
#include "random.hpp"
#include "lua_kit.h"

//[min,max]
static int lrand_range(lua_State* L)
{
	int64_t v_min = (int64_t)luaL_checkinteger(L, 1);
	int64_t v_max = (int64_t)luaL_checkinteger(L, 2);
	if (v_min > v_max)
	{
		return luaL_error(L, "argument error: #1:%lld > #2:%lld",v_min,v_max);
	}
	auto res = lrandom::rand_range(v_min, v_max);
	lua_pushinteger(L, res);
	return 1;
}

//[min,max]
static int lrand_range_some(lua_State* L)
{
    int64_t v_min = (int64_t)luaL_checkinteger(L, 1);
    int64_t v_max = (int64_t)luaL_checkinteger(L, 2);
    int64_t v_count = (int64_t)luaL_checkinteger(L, 3);
    int64_t v_num = v_max - v_min + 1;
    if (v_count <= 0 || v_num < v_count)
    {
        return luaL_error(L, "rand_range_some range count:%lld < num:%lld",v_count,v_num);
    }
    std::vector<int64_t>* vec = new std::vector<int64_t>(v_num);
    std::iota(vec->begin(), vec->end(), v_min);
    lua_createtable(L, (int)v_count, 0);
    int count = 0;
    while (v_count > 0)
    {
        auto index = lrandom::rand_range((size_t)0, vec->size() - 1);
        lua_pushinteger(L, (*vec)[index]);
        lua_rawseti(L, -2, ++count);
        (*vec)[index] = (*vec)[vec->size() - 1];
        vec->pop_back();
        --v_count;
    }
    delete vec;
    return 1;
}

//[min,max)
static int lrandf_range(lua_State* L)
{
    double v_min = (double)luaL_checknumber(L, 1);
    double v_max = (double)luaL_checknumber(L, 2);
    auto res = lrandom::randf_range(v_min, v_max);
    lua_pushnumber(L, res);
    return 1;
}

static int lrandf_percent(lua_State* L)
{
    double v = (double)luaL_checknumber(L, 1);
    auto res = lrandom::randf_percent(v);
    lua_pushboolean(L, res);
    return 1;
}

static int lrand_weight(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);
    auto values = luakit::lua_to_native<luakit::reference>(L, 1).to_sequence<std::vector<int64_t>,int64_t>();
    auto weights = luakit::lua_to_native<luakit::reference>(L, 2).to_sequence<std::vector<int64_t>, int64_t>();
    
	if (values.size() != weights.size() || values.size() == 0) {
		return luaL_error(L, "lrand_weight table empty or values size:%d != weights size:%d", values.size(), weights.size());
	}
    int64_t sum = std::accumulate(weights.begin(), weights.end(), int64_t{0});
    if (sum == 0) {
        return 0;
    }
    int64_t cutoff = lrandom::rand_range(int64_t{0}, sum - 1);
    auto vi = values.begin();
    auto wi = weights.begin();
    while (cutoff >= *wi)
    {
        cutoff -= *wi++;
        ++vi;
    }
    lua_pushinteger(L, *vi);
    return 1;
}

static int lrand_weight_some(lua_State* L)
{
    luaL_checktype(L, 1, LUA_TTABLE);
    luaL_checktype(L, 2, LUA_TTABLE);    
    auto v = luakit::lua_to_native<luakit::reference>(L, 1).to_sequence<std::vector<int64_t>, int64_t>();
    auto w = luakit::lua_to_native<luakit::reference>(L, 2).to_sequence<std::vector<int64_t>, int64_t>();
    int64_t count = luaL_checkinteger(L, 3);
    if (v.size() != w.size() || v.size() == 0 || count < 0 || (int64_t)v.size() < count)
    {
        return luaL_error(L, "lrand_weight_some table empty or values size:%d != weights size:%d,count:%d", v.size(),w.size(),count);
    }
    lua_createtable(L, (int)count, 0);
    for (int64_t i = 0; i < count; ++i)
    {
        int64_t sum = std::accumulate(w.begin(), w.end(), int64_t{0});
        if (sum == 0)
        {
            lua_pop(L, 1); // pop table
            return 0;
        }
        int64_t cutoff = lrandom::rand_range(int64_t{0}, sum - 1);
        auto idx = 0;
        while (cutoff >= w[idx])
        {
            cutoff -= w[idx];
            ++idx;
        }
        lua_pushinteger(L, v[idx]);
        lua_rawseti(L, -2, i + 1);
        v[idx] = v[v.size() - 1];
        v.pop_back();
        w[idx] = w[w.size() - 1];
        w.pop_back();
    }
    return 1;
}

luakit::lua_table open_lrandom(lua_State* L) {
    luakit::kit_state lua(L);
    auto lrandom = lua.new_table();
    lrandom.set_function("rand_range", lrand_range);
    lrandom.set_function("rand_range_some", lrand_range_some);
    lrandom.set_function("randf_range", lrandf_range);
    lrandom.set_function("randf_percent", lrandf_percent);
    lrandom.set_function("rand_weight", lrand_weight);
    lrandom.set_function("rand_weight_some", lrand_weight_some);
    return lrandom;
}

extern "C" {
    LUAMOD_API int luaopen_lrandom(lua_State* L){
        return open_lrandom(L).push_stack();
    }
}
