#include <lua.h>
#include <lauxlib.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "buffer.h"
#include "serialize.h"

#define LUA_ENCODE_SIZE     64
#define LUA_SERIALIZE_SIZE  256

#define  LUA_BUFFER_META    "_LUA_BUFFER_META"

int lencode(lua_State* L) {
    //分配资源
    uint32_t size = 0;
    var_buffer* binary = buffer_alloc(LUA_ENCODE_SIZE);
    buffer_apend(binary, (uint8_t*)&size, sizeof(uint32_t));
    encode(L, binary, 0);
    //写入size
    size = buffer_size(binary) - sizeof(uint32_t);
    buffer_copy(binary, 0, (uint8_t*)&size, sizeof(uint32_t));
    //返回
    size_t len;
    uint8_t* byte = buffer_data(binary, &len);
    lua_pushlstring(L, byte, len);
    buffer_close(binary);
    return 1;
}

int ldecode(lua_State* L) {
    size_t len;
    uint8_t* byte = (uint8_t*)luaL_checklstring(L, 1, &len);
    var_buffer* binary = buffer_alloc(LUA_ENCODE_SIZE);
    if (!buffer_apend(binary, byte, len)) {
        buffer_close(binary);
        return luaL_error(L, "deserialize buff append");
    }
    uint32_t size;
    lua_settop(L, 0);
    buffer_read(binary, (uint8_t*)&size, sizeof(uint32_t));
    decode(L, binary);
    buffer_close(binary);
    return lua_gettop(L);
}

int lserialize(lua_State* L) {
    var_buffer* binary = buffer_alloc(LUA_SERIALIZE_SIZE);
    serialize(L, binary, 1, 1, luaL_optinteger(L, 2, 0));
    size_t len;
    uint8_t* byte = buffer_data(binary, &len);
    lua_pushlstring(L, byte, len);
    buffer_close(binary);
    return 1;
}

int lunserialize(lua_State* L) {
    size_t len;
    uint8_t* tmp = "return ";
    var_buffer* binary = buffer_alloc(LUA_SERIALIZE_SIZE);
    uint8_t* data = (uint8_t*)luaL_checklstring(L, 1, &len);
    buffer_apend(binary, tmp, strlen(tmp));
    buffer_apend(binary, data, len);
    uint8_t* byte = buffer_data(binary, &len);
    if (luaL_loadbufferx(L, byte, len, "unserialize", "bt") == 0) {
        if (lua_pcall(L, 0, 1, 0) == 0) {
            buffer_close(binary);
            return 1;
        }
    }
    return luaL_error(L, lua_tostring(L, -1));
}

static int lbuffer_size(lua_State* L) {
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    lua_pushinteger(L, buffer_size(buf));
    return 1;
}

static int lbuffer_close(lua_State* L) {
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    buffer_close(buf);
    return 0;
}

static int lbuffer_reset(lua_State* L) {
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    buffer_reset(buf);
    return 0;
}

static int lbuffer_append(lua_State* L) {
    size_t len;
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    uint8_t* data = (uint8_t*)luaL_checklstring(L, 2, &len);
    lua_pushinteger(L, buffer_apend(buf, data, len));
    return 1;
}

static int lbuffer_erase(lua_State* L) {
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    size_t erase_len = lua_tointeger(L, 2);
    lua_pushinteger(L, buffer_erase(buf, erase_len));
    return 1;
}

static int lbuffer_copy(lua_State* L) {
    size_t len;
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    uint8_t* data = (uint8_t*)luaL_checklstring(L, 2, &len);
    size_t offset = lua_tointeger(L, 3);
    lua_pushinteger(L, buffer_copy(buf, offset, data, len));
    return 1;
}

static int lbuffer_peek(lua_State* L) {
    size_t len = lua_tointeger(L, 2);
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    uint8_t* data = buffer_peek(buf, len);
    if (data) {
        lua_pushlstring(L, data, len);
        return 1;
    }
    return 0;
}

static int lbuffer_read(lua_State* L) {
    size_t len = lua_tointeger(L, 2);
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    uint8_t* data = (uint8_t*)malloc(len);
    size_t size = buffer_read(buf, data, len);
    if (size > 0) {
        lua_pushlstring(L, data, len);
    }
    free(data);
    return size > 0 ? 1 : 0;
}

static int lbuffer_data(lua_State* L) {
    size_t len;
    var_buffer* buf = (var_buffer*)lua_touserdata(L, 1);
    uint8_t* data = buffer_data(buf, &len);
    lua_pushlstring(L, data, len);
    lua_pushinteger(L, len);
    return 2;
}

static const luaL_Reg lbuffer_reg[] = {
    { "size", lbuffer_size },
    { "copy", lbuffer_copy },
    { "peek", lbuffer_peek },
    { "read", lbuffer_read },
    { "data", lbuffer_data },
    { "close", lbuffer_close },
    { "reset", lbuffer_reset },
    { "erase", lbuffer_erase },
    { "append", lbuffer_append },
    { NULL, NULL }
};

static int lbuffer_create(lua_State* L) {
    size_t size = lua_tointeger(L, 1);
    var_buffer* buff = buffer_alloc(size);
    lua_pushlightuserdata(L, (void*)buff);
    if (luaL_getmetatable(L, LUA_BUFFER_META) != LUA_TTABLE) {
        lua_pop(L, 1);
        luaL_newmetatable(L, LUA_BUFFER_META);
        luaL_newlib(L, lbuffer_reg);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}

LBUFF_API int luaopen_lbuffer(lua_State* L) {
    luaL_Reg l[] = {
        { "encode", lencode },
        { "decode", ldecode },
        { "serialize", lserialize },
        { "unserialize", lunserialize },
        { "create", lbuffer_create },
        { NULL, NULL },
    };
    luaL_newlib(L, l);
    return 1;
}
