#include <algorithm>
#include "zset.hpp"

extern "C" {
    #include "lua.h"
    #include "lauxlib.h"
}

#define METANAME "lzet"

struct zset_proxy
{
    lzset::zset* zset;
};

static int lupdate(lua_State* L)
{
    int param_count = lua_gettop(L);
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (param_count < 3 || nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer or param less");
    }
    int64_t key = (int64_t)luaL_checkinteger(L, 2);
    std::vector<int64_t> scores;
    for (size_t i=3;i<=param_count;++i)
    {
        scores.push_back( (int64_t)luaL_checkinteger(L, i));
    }
    scores.shrink_to_fit();
    auto ret = proxy->zset->update(key, std::move(scores));
    if (ret == 1)
    {
        return luaL_error(L, "the update size is not eq \n");
    }
    lua_pushinteger(L, ret);
    return 1;
}

static int lprepare(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    proxy->zset->prepare();
    return 0;
}

static int lrank(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    int64_t key = (int64_t)luaL_checkinteger(L, 2);
    lua_pushinteger(L, proxy->zset->rank(key));
    return 1;
}

static int lscore(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    int64_t key = (int64_t)luaL_checkinteger(L, 2);
    const auto& scores = proxy->zset->score(key);
    lua_createtable(L, scores.size(), 0);
    for (auto i=0;i<scores.size();++i)
    {
        lua_pushinteger(L, scores[i]);
        lua_rawseti(L, -2, i+1);
    }
    return 1;
}

static int lhas(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    int64_t key = (int64_t)luaL_checkinteger(L, 2);
    lua_pushboolean(L, proxy->zset->has(key)?1:0);
    return 1;
}

static int lsize(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    lua_pushinteger(L, proxy->zset->size());
    return 1;
}

static int lclear(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    proxy->zset->clear();
    return 0;
}

static int lerase(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    int64_t key = (int64_t)luaL_checkinteger(L, 2);
    lua_pushinteger(L, proxy->zset->erase(key));
    return 1;
}

static int lrange(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (nullptr == proxy || nullptr == proxy->zset)
    {
        return luaL_error(L, "invalid lua-zset pointer");
    }
    uint32_t start = (uint32_t)luaL_checkinteger(L, 2);
    uint32_t end = (uint32_t)luaL_checkinteger(L, 3);

    auto count = end - start + 1;
    if (end < start || count == 0)
    {
        return 0;
    }
    proxy->zset->prepare();
    auto iter = proxy->zset->start(start);
    if (iter == proxy->zset->end())
    {
        return 0;
    }
    lua_createtable(L, std::min(32U, count), 0);
    int idx = 1;
    for (; iter != proxy->zset->end() && count > 0; ++iter)
    {
        lua_newtable(L);
        lua_pushinteger(L, (*iter)->key);
        lua_rawseti(L, -2, 1);
        lua_pushinteger(L, (*iter)->rank);
        lua_rawseti(L, -2, 2);
        for (auto i=0;i<(*iter)->scores.size();++i)
        {
            lua_pushinteger(L, (*iter)->scores[i]);
            lua_rawseti(L, -2, 3 + i);
        }
        lua_rawseti(L, -2, idx++);
        --count;
    }
    return 1;
};

static int lrelease(lua_State* L)
{
    zset_proxy* proxy = (zset_proxy*)lua_touserdata(L, 1);
    if (proxy && proxy->zset)
    {
        delete proxy->zset;
        proxy->zset = nullptr;
    }
    return 0;
}

static int lcreate(lua_State* L)
{
    size_t max_count = (size_t)luaL_checkinteger(L, 1);
    size_t score_count = (size_t)luaL_checkinteger(L, 2);
    size_t len = 0;
    const char* fmt = luaL_optlstring(L, 3, "><>>", &len);
    if (len != score_count)
        return luaL_error(L, "fmt need %d chars '>' or '<' for compare",score_count);
    for (size_t i = 0; i < len; ++i)
    {
        if(fmt[i]!='>'&&fmt[i]!='<')
            return luaL_error(L, "fmt need %d chars '>' or '<' for compare",score_count);
    }
    zset_proxy* proxy = (zset_proxy*)lua_newuserdatauv(L, sizeof(zset_proxy), 0);
    proxy->zset = new lzset::zset(max_count,score_count, fmt);
    if (luaL_newmetatable(L, METANAME))//mt
    {
        luaL_Reg l[] = {
            { "update", lupdate },
            { "prepare",lprepare },
            { "has", lhas},
            { "rank", lrank},
            { "score", lscore},
            { "range", lrange},
            { "clear", lclear},
            { "size", lsize},
            { "erase", lerase},
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

extern "C" {
    LUAMOD_API int luaopen_lzset(lua_State* L){
        luaL_Reg l[] = {
            {"new",lcreate},
            {"release",lrelease },
            {NULL,NULL}
        };
        luaL_checkversion(L);
        luaL_newlib(L, l);
        return 1;
    }
}
