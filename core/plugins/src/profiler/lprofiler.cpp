
#include "profiler.h"
#include "lua_kit.h"

namespace lprofiler {

    thread_local ProfileManager thread_profiler;
    thread_local std::string err_msg;

    static int start(lua_State* L, const char* node_name) {
        auto ret = thread_profiler.startProfile((size_t)L, node_name, err_msg);
        if (ret == 0) {
            return luaL_error(L, "start error: %s!", err_msg.c_str());
        }
        lua_pushinteger(L, ret);
        return 1;
    }

    static int stop(lua_State* L, const char* node_name) {
        auto ret = thread_profiler.stopProfile((size_t)L, node_name, err_msg);
        if (ret == 0) {
            return luaL_error(L, "stop error: %s!", err_msg.c_str());
        }
        lua_pushinteger(L, ret);
        return 1;
    }

    luakit::lua_table open_lprofiler(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lprofiler = kit_state.new_table();
        lprofiler.set_function("init", []() { thread_profiler.init(); });
        lprofiler.set_function("shutdown", []() { thread_profiler.shutdown(); });
        lprofiler.set_function("start", start);
        lprofiler.set_function("stop", stop);
        lprofiler.set_function("info", []() { return thread_profiler.info(); });

        return lprofiler;
    }
}

extern "C" {
    LUALIB_API int luaopen_lprofiler(lua_State* L) {
        lprofiler::thread_profiler.init();
        auto lprof = lprofiler::open_lprofiler(L);
        return lprof.push_stack();
    }
}
