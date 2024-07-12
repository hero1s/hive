#define LUA_LIB

#include "lua_kit.h"
#include "algo.hpp"

using namespace luakit;
using namespace lalgo;

namespace lalgo {

    
    lua_table open_lalgo(lua_State* L) {
        kit_state kit_state(L);
        lua_table lalgo = kit_state.new_table();
        lalgo.set_function("is_prime", [](int n) { return isPrime(n); });

        return lalgo;
    }
}

extern "C" {
    LUALIB_API int luaopen_lalgo(lua_State* L) {
        auto algo = lalgo::open_lalgo(L);
        return algo.push_stack();
    }
}
