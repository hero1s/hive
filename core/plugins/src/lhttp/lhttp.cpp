
#include "http.h"

namespace lhttp {

    static http_request* create_request(lua_State* L) {
        return new http_request();
    }

    static http_response* create_response(lua_State* L) {
        return new http_response();
    }

    luakit::lua_table open_lhttp(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lhttp = kit_state.new_table();
        lhttp.set_function("create_request", create_request);
        lhttp.set_function("create_response", create_response);
        kit_state.new_class<http_request>(
            "url", &http_request::url,
            "body", &http_request::body,
            "method", &http_request::method,
            "chunked", &http_request::chunked,
            "version", &http_request::version,
            "chunk_size", &http_request::chunk_size,
            "content_size", &http_request::content_size,
            "get_headers", &http_request::get_headers,
            "get_params", &http_request::get_params,
            "get_header", &http_request::get_header,
            "get_param", &http_request::get_param,
            "parse", &http_request::parse
            );
        kit_state.new_class<http_response>(
            "status", &http_response::status,
            "content", &http_response::content,
            "serialize", &http_response::serialize,
            "set_header", &http_response::set_header
            );
        return lhttp;
    }
}

extern "C" {
    LUALIB_API int luaopen_lhttp(lua_State* L) {
        auto lhttp = lhttp::open_lhttp(L);
        return lhttp.push_stack();
    }
}
