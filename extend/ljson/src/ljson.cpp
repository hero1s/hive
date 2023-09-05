#define LUA_LIB

#include "ljson.h"

namespace ljson {
    thread_local yyjson thread_json;
    thread_local jsoncodec thread_codec;
    
    static jsoncodec* json_codec() {
        thread_codec.set_json(&thread_json);
        return &thread_codec;
    }

    luakit::lua_table open_ljson(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto ljson = kit_state.new_table();
        ljson.set_function("jsoncodec", json_codec);
        ljson.set_function("pretty", [](lua_State* L) { return thread_json.pretty(L); });
        ljson.set_function("encode", [](lua_State* L) { return thread_json.encode(L); });
        ljson.set_function("decode", [](lua_State* L) { return thread_json.decode(L); });
        return ljson;
    }
}

extern "C" {
    LUALIB_API int luaopen_ljson(lua_State* L) {
        auto ljson = ljson::open_ljson(L);
        return ljson.push_stack();
    }
}