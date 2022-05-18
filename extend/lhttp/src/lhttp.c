#include "http.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#define  LUA_HTTP_REQUEST_META  "_LUA_HTTP_REQUEST_META"
#define  LUA_HTTP_RESPONSE_META "_LUA_HTTP_RESPONSE_META"

static int lrequest_response(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        int code = lua_tointeger(L, 2);
        const char* type = lua_tostring(L, 3);
        const char* message = lua_tostring(L, 4);
        http_string_t res = http_request_response(req, code, type, message);
        lua_pushlstring(L, res.buf, res.len);
        return 1;
    }
    return 0;
}

static int lrequest_process(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_process_request(req);
    }
    return 0;
}

static int lrequest_gc(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_clean_request(req);
    }
    return 0;
}

static int lrequest_append(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        size_t len;
        const char* buf = lua_tolstring(L, 2, &len);
        int alen = http_stream_append(&req->stream, buf, len);
        lua_pushinteger(L, alen);
        return 1;
    }
    return 0;
}

static int lrequest_state(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        lua_pushinteger(L, req->state);
        return 1;
    }
    return 0;
}

static int lrequest_method(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_string_t method = http_request_method(req);
        lua_pushlstring(L, method.buf, method.len);
        return 1;
    }
    return 0;
}

static int lrequest_url(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_string_t target = http_request_url(req);
        lua_pushlstring(L, target.buf, target.len);
        return 1;
    }
    return 0;
}

static int lrequest_body(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_string_t target = http_request_body(req);
        lua_pushlstring(L, target.buf, target.len);
        return 1;
    }
    return 0;
}

static int lrequest_chunk(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        http_string_t chunk = http_request_chunk(req);
        lua_pushlstring(L, chunk.buf, chunk.len);
        return 1;
    }
    return 0;
}

static int lrequest_is_chunk(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        int ischunk = http_request_has_flag(req, HTTP_FLG_CHUNK);
        lua_pushboolean(L, ischunk > 0);
        return 1;
    }
    return 0;
}

static int lrequest_header(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        const char* key = lua_tostring(L, 2);
        http_string_t value = http_request_header(req, key);
        lua_pushlstring(L, value.buf, value.len);
        return 1;
    }
    return 0;
}

static int lrequest_query(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        const char* key = lua_tostring(L, 2);
        http_string_t value = http_request_query(req, key);
        lua_pushlstring(L, value.buf, value.len);
        return 1;
    }
    return 0;
}

static int lrequest_headers(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        int iter = 0;
        http_string_t key, val;
        lua_newtable(L);
        while (http_request_headers_iterator(req, &key, &val, &iter)) {
            lua_pushlstring(L, key.buf, key.len);
            lua_pushlstring(L, val.buf, val.len);
            lua_settable(L, -3);
        }
        return 1;
    }
    return 0;
}

static int lrequest_querys(lua_State* L) {
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 1, LUA_HTTP_REQUEST_META);
    if (req) {
        int iter = 0;
        http_string_t key, val;
        lua_newtable(L);
        while (http_request_querys_iterator(req, &key, &val, &iter)) {
            lua_pushlstring(L, key.buf, key.len);
            lua_pushlstring(L, val.buf, val.len);
            lua_settable(L, -3);
        }
        return 1;
    }
    return 0;
}

static int lresponse_gc(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    if (res) {
        http_clean_response(res);
    }
    return 0;
}

static int lresponse_status(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    if (res) {
        int status = lua_tointeger(L, 2);
        http_response_status(res, status);
    }
    return 0;
}

static int lresponse_body(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    if (res) {
        size_t len;
        const char* body = lua_tolstring(L, 2, &len);
        http_response_body(res, body, len);
    }
    return 0;
}

static int lresponse_header(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    if (res) {
        const char* key = lua_tostring(L, 2);
        const char* val = lua_tostring(L, 3);
        http_response_header(res, key, val);
    }
    return 0;
}

static int lresponse_respond(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 2, LUA_HTTP_REQUEST_META);
    if (res && req) {
        http_string_t respond = http_respond(req, res);
        lua_pushlstring(L, respond.buf, respond.len);
        return 1;
    }
    return 0;
}

static int lresponse_chunk(lua_State* L) {
    http_response_t* res = (http_response_t*)luaL_checkudata(L, 1, LUA_HTTP_RESPONSE_META);
    http_request_t* req = (http_request_t*)luaL_checkudata(L, 2, LUA_HTTP_REQUEST_META);
    if (res && req) {
        http_string_t respond;
        if (lua_gettop(L) > 2) {
            respond = http_respond_chunk_end(req, res);
        } else {
            respond = http_respond_chunk(req, res);
        }
        lua_pushlstring(L, respond.buf, respond.len);
        return 1;
    }
    return 0;
}

static const luaL_Reg lrequest[] = {
    { "url", lrequest_url },
    { "body", lrequest_body },
    { "state", lrequest_state },
    { "query", lrequest_query },
    { "chunk", lrequest_chunk },
    { "header", lrequest_header },
    { "querys", lrequest_querys },
    { "append", lrequest_append },
    { "method", lrequest_method },
    { "headers", lrequest_headers },
    { "process", lrequest_process },
    { "response", lrequest_response },
    { "is_chunk", lrequest_is_chunk },
    { "__gc", lrequest_gc },
    { NULL, NULL }
};

static const luaL_Reg lresponse[] = {
    { "set_body", lresponse_body },
    { "respond", lresponse_respond },
    { "set_status", lresponse_status },
    { "set_header", lresponse_header },
    { "respond_chunk", lresponse_chunk },
    { "__gc", lresponse_gc },
    { NULL, NULL }
};

static int lhttp_create_request(lua_State* L) {
    http_request_t* req = (http_request_t*)lua_newuserdata(L, sizeof(http_request_t));
    memset(req, 0, sizeof(http_request_t));
    http_request_reset(req);
    if (luaL_getmetatable(L, LUA_HTTP_REQUEST_META) != LUA_TTABLE) {
        lua_pop(L, 1);
        luaL_newmetatable(L, LUA_HTTP_REQUEST_META);
        luaL_setfuncs(L, lrequest, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    return 1;
}

static int lhttp_create_response(lua_State* L) {
    http_response_t* res = (http_response_t*)lua_newuserdata(L, sizeof(http_response_t));
    memset(res, 0, sizeof(http_response_t));
    if (luaL_getmetatable(L, LUA_HTTP_RESPONSE_META) != LUA_TTABLE) {
        lua_pop(L, 1);
        luaL_newmetatable(L, LUA_HTTP_RESPONSE_META);
        luaL_setfuncs(L, lresponse, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    lua_setmetatable(L, -2);
    res->status = 200;
    return 1;
}

static const luaL_Reg lhttp[] = {
    { "create_request", lhttp_create_request },
    { "create_response", lhttp_create_response },
    { NULL, NULL }
};

LHTTP_API int luaopen_lhttp(lua_State* L) {
    luaL_newlib(L, lhttp);
    return 1;
}
