#define LUA_LIB

#include "jps_mgr.h"

#include "lua_kit.h"

extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

namespace ljps {
    luakit::lua_table open_ljps(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto ljps = kit_state.new_table();
        kit_state.new_class<CJpsMgr>(
            "init", &CJpsMgr::init,
            "find_path", &CJpsMgr::find_path,
            "enable_debug",&CJpsMgr::enable_debug
            );
        ljps.set_function("new", []() { return new CJpsMgr(); });
        return ljps;
    }
}

extern "C" {
    LUALIB_API int luaopen_ljps(lua_State* L) {
        return ljps::open_ljps(L).push_stack();
    }
}