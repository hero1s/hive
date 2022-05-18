#define LUA_LIB
#include <stdlib.h>
#include <assert.h>
#include <stdbool.h>
#include <string.h>
#include <curl/curl.h>

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#define MAX(a, b)               (((a) > (b)) ? (a) : (b))

#define LUA_CURL_TIMEOUT_MS     3000
#define LUA_CURL_REQUEST_META   "_LUA_CURL_REQUEST_META"

typedef struct lua_curl {
    CURLM* curlm;
    CURL* encode_curl;
} lua_curl_t;

static lua_curl_t lcurl = { 0 };

typedef struct lcurl_request {
    CURL* curl;
    struct curl_slist* header;
    char error[CURL_ERROR_SIZE];
    char* content;
    size_t content_length;
    size_t content_maxlength;
    bool content_realloc_failed;
} lcurl_request_t;

static CURL* lcurl_realquery(CURLcode* ret_result) {
    while (true) {
        int msgs_in_queue;
        CURLMsg* curlmsg = curl_multi_info_read(lcurl.curlm, &msgs_in_queue);
        if (!curlmsg)
            return NULL;
        if (curlmsg->msg != CURLMSG_DONE)
            continue;
        *ret_result = curlmsg->data.result;
        return curlmsg->easy_handle;
    }
}

static int lcurl_query(lua_State* L) {
    CURLcode handle_result;
    CURL* handle = lcurl_realquery(&handle_result);
    if (handle) {
        lua_pushlightuserdata(L, handle);
        lua_pushinteger(L, handle_result);
        return 2;
    }
    int running_handles;
    CURLMcode perform_result = curl_multi_perform(lcurl.curlm, &running_handles);
    if (perform_result != CURLM_OK && perform_result != CURLM_CALL_MULTI_PERFORM) {
        lua_pushnil(L);
        lua_pushstring(L, "lcurl query failed");
        return 2;
    }
    return 0;
}

static size_t write_callback(char* buffer, size_t block_size, size_t count, void* arg) {
    lcurl_request_t* request = (lcurl_request_t*)arg;
    assert(request);

    size_t length = block_size * count;
    if (request->content_realloc_failed) {
        return length;
    }
    if (request->content_length + length > request->content_maxlength) {
        request->content_maxlength = MAX(request->content_maxlength, request->content_length + length);
        request->content_maxlength = MAX(request->content_maxlength, 512);
        request->content_maxlength = 2 * request->content_maxlength;
        void* new_content = (char*)realloc(request->content, request->content_maxlength);
        if (!new_content) {
            request->content_realloc_failed = true;
            return length;
        }
        request->content = (char *)new_content;
    }
    memcpy(request->content + request->content_length, buffer, length);
    request->content_length += length;
    return length;
}

static void curl_cleanup_request(lcurl_request_t* request) {
    if (request && lcurl.curlm) {
        curl_multi_remove_handle(lcurl.curlm, request->curl);
        curl_easy_cleanup(request->curl);
        curl_slist_free_all(request->header);
        if (request->content) {
            free(request->content);
        }
    }
}

static int lcurl_request_gc(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (request) {
        curl_cleanup_request(request);
    }
    return 0;
}

static int lcurl_getrespond(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushnil(L);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    if (request->content_realloc_failed) {
        strncpy(request->error, "not enough memory.", CURL_ERROR_SIZE);
    }
    if (request->error[0] == '\0') {
        lua_pushlstring(L, request->content, request->content_length);
        return 1;
    }
    lua_pushlstring(L, request->content, request->content_length);
    lua_pushstring(L, request->error);
    return 2;
}

static int lcurl_getinfo(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushnil(L);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    lua_newtable(L);
    char* ip = NULL;
    if (curl_easy_getinfo(request->curl, CURLINFO_PRIMARY_IP, &ip) == CURLE_OK) {
        lua_pushstring(L, ip);
        lua_setfield(L, -2, "ip");
    }
    long port = 0;
    if (curl_easy_getinfo(request->curl, CURLINFO_LOCAL_PORT, &port) == CURLE_OK) {
        lua_pushinteger(L, port);
        lua_setfield(L, -2, "port");
    }
    double content_length = 0;
    if (curl_easy_getinfo(request->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD, &content_length) == CURLE_OK) {
        lua_pushnumber(L, content_length);
        lua_setfield(L, -2, "content_length");
    }
    char* content_type = NULL;
    if (curl_easy_getinfo(request->curl, CURLINFO_CONTENT_TYPE, &content_type) == CURLE_OK) {
        lua_pushnumber(L, content_length);
        lua_setfield(L, -2, "content_type");
    }
    long response_code = 0;
    if (curl_easy_getinfo(request->curl, CURLINFO_RESPONSE_CODE, &response_code) == CURLE_OK) {
        lua_pushinteger(L, response_code);
        lua_setfield(L, -2, "code");
    }
    if (request->content_realloc_failed) {
        lua_pushboolean(L, request->content_realloc_failed);
        lua_setfield(L, -2, "content_failed");
    }
    return 1;
}

static int lcurl_getprogress(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushnil(L);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    double total = 0.0f;
    double finished = 0.0f;
    int is_uploadprogress = lua_toboolean(L, 2);
    if(!is_uploadprogress) {
        if (curl_easy_getinfo(request->curl, CURLINFO_SIZE_DOWNLOAD, &finished) != CURLE_OK)
            return 0;
        if (curl_easy_getinfo(request->curl, CURLINFO_CONTENT_LENGTH_DOWNLOAD, &total) != CURLE_OK)
            return 0;
    }
    else {
        if (curl_easy_getinfo(request->curl, CURLINFO_SIZE_UPLOAD, &finished) != CURLE_OK)
            return 0;
        if (curl_easy_getinfo(request->curl, CURLINFO_CONTENT_LENGTH_UPLOAD, &total) != CURLE_OK)
            return 0;
    }
    lua_pushnumber(L, finished);
    lua_pushnumber(L, total);
    return 2;
}

static int lcurl_set_headers(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    int i;
    int top = lua_gettop(L);
    for (i = 2; i <= top; ++i) {
        const char* str = lua_tostring(L, i);
        request->header = curl_slist_append(request->header, str);
    }
    if (request->header) {
        curl_easy_setopt(request->curl, CURLOPT_HTTPHEADER, request->header);
    }
    lua_pushboolean(L, true);
    return 1;
}

static int lcurl_call_request(lua_State* L, lcurl_request_t* request) {
    if (lua_gettop(L) > 1) {
        if (lua_type(L, 2) == LUA_TSTRING) {
            size_t length;
            const char* post = lua_tolstring(L, 2, &length);
            curl_easy_setopt(request->curl, CURLOPT_POSTFIELDS, post);
            curl_easy_setopt(request->curl, CURLOPT_POSTFIELDSIZE, length);
        }
    }
    if (curl_multi_add_handle(lcurl.curlm, request->curl) == CURLM_OK) {
        lua_pushboolean(L, true);
        return 1;
    }
    curl_cleanup_request(request);
    lua_pushboolean(L, false);
    lua_pushstring(L, "curl_multi_add_handle failed!");
    return 2;
}

static int lcurl_call_get(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    return lcurl_call_request(L, request);
}

static int lcurl_call_post(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    curl_easy_setopt(request->curl, CURLOPT_POST, 1L);
    return lcurl_call_request(L, request);
}

static int lcurl_call_put(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    curl_easy_setopt(request->curl, CURLOPT_CUSTOMREQUEST, "PUT");
    return lcurl_call_request(L, request);
}

static int lcurl_call_del(lua_State* L) {
    lcurl_request_t* request = (lcurl_request_t*)luaL_checkudata(L, 1, LUA_CURL_REQUEST_META);
    if (!request) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lcurl_request is nil!");
        return 2;
    }
    curl_easy_setopt(request->curl, CURLOPT_CUSTOMREQUEST, "DELETE");
    return lcurl_call_request(L, request);
}

static const luaL_Reg lrequest[] = {
    { "get_info", lcurl_getinfo },
    { "call_get", lcurl_call_get },
    { "call_put", lcurl_call_put },
    { "call_del", lcurl_call_del },
    { "call_post", lcurl_call_post },
    { "get_respond", lcurl_getrespond },
    { "set_headers", lcurl_set_headers },
    { "get_progress", lcurl_getprogress },
    { "__gc", lcurl_request_gc },
    { NULL, NULL }
};

static int lcurl_create_request(lua_State* L) {
    size_t timeout_ms = LUA_CURL_TIMEOUT_MS;
    const char* url = lua_tostring(L, 1);
    if (lua_gettop(L) > 1) {
        timeout_ms = luaL_optinteger(L, 2, LUA_CURL_TIMEOUT_MS);
    }
    CURL* handle = curl_easy_init();
    if (!handle) {
        lua_pushnil(L);
        lua_pushstring(L, "curl_easy_init failed!");
        return 2;
    }
    lcurl_request_t* request = (lcurl_request_t*)lua_newuserdata(L, sizeof(lcurl_request_t));
    memset(request, 0, sizeof(lcurl_request_t));
    if (luaL_getmetatable(L, LUA_CURL_REQUEST_META) != LUA_TTABLE) {
        lua_pop(L, 1);
        luaL_newmetatable(L, LUA_CURL_REQUEST_META);
        luaL_setfuncs(L, lrequest, 0);
        lua_pushvalue(L, -1);
        lua_setfield(L, -2, "__index");
    }
    curl_easy_setopt(handle, CURLOPT_URL, url);
    curl_easy_setopt(handle, CURLOPT_NOSIGNAL, 1);;
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, request);
    curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS, timeout_ms);
    curl_easy_setopt(handle, CURLOPT_ERRORBUFFER, request->error);
    curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS, timeout_ms / 2);
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(handle, CURLOPT_SSL_VERIFYPEER, false);
    curl_easy_setopt(handle, CURLOPT_SSL_VERIFYHOST, false);
    curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION, 1L);
    request->curl = handle;
    lua_setmetatable(L, -2);
    lua_pushlightuserdata(L, handle);
    return 2;
}

static int lcurl_destory(lua_State* L) {
    if (lcurl.encode_curl) {
        curl_easy_cleanup(lcurl.encode_curl);
        lcurl.encode_curl = NULL;
    }
    if (lcurl.curlm) {
        curl_multi_cleanup(lcurl.curlm);
        lcurl.curlm = NULL;
    }
    curl_global_cleanup();
    return 0;
}

static int lcurl_url_encode(lua_State* L) {
    if (!lcurl.encode_curl) {
        lcurl.encode_curl = curl_easy_init();
    }
    size_t length = 0;
    const char* str = lua_tolstring(L, 1, &length);
    if (length > 0) {
        char* output = curl_easy_escape(lcurl.encode_curl, str, (int)length);
        if (output) {
            lua_pushstring(L, output);
            curl_free(output);
            return 1;
        }
    }
    lua_pushstring(L, "");
    return 1;
}

static const luaL_Reg lcurl_funs[] = {
    { "query", lcurl_query },
    { "destory", lcurl_destory },
    { "url_encode", lcurl_url_encode },
    { "create_request", lcurl_create_request },
    { NULL, NULL }
};

LUALIB_API int luaopen_lcurl(lua_State* L) {
    if (!lcurl.curlm) {
        curl_version_info_data* data = curl_version_info(CURLVERSION_NOW);
        if (data->version_num < 0x070F04) {
            return luaL_error(L, "requires 7.15.4 or higher curl, current version is %s", data->version);
        }
        curl_global_init(CURL_GLOBAL_ALL);
        CURLM* curlm = curl_multi_init();
        if (!curlm) {
            curl_global_cleanup();
            return luaL_error(L, "lcurl create failed");
        }
        lcurl.curlm = curlm;
        lcurl.encode_curl = NULL;
    }
    luaL_newlib(L, lcurl_funs);
    return 1;
}
