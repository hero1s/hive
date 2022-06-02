#pragma once

#include <set>
#include <map>
#include <list>
#include <tuple>
#include <string>
#include <vector>
#include <utility>
#include <cstdint>
#include <functional>
#include <type_traits>
#include <assert.h>

extern "C"
{
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

namespace luakit {

#define MAX_LUA_META_KEY 128

    //异常处理器
    using exception_handler = std::function<void(std::string err)>;

    template<typename T>
    const char* lua_get_meta_name() {
        static char meta_name[MAX_LUA_META_KEY];
        using OT = std::remove_cv_t<std::remove_pointer_t<T>>;
        snprintf(meta_name, MAX_LUA_META_KEY, "__lua_class_meta_%zu__", typeid(OT).hash_code());
        return meta_name;
    }

    template<typename T>
    const char* lua_get_object_key(void* obj) {
        static char objkey[MAX_LUA_META_KEY];
        using OT = std::remove_cv_t<std::remove_pointer_t<T>>;
        snprintf(objkey, MAX_LUA_META_KEY, "%p@%zu", obj, typeid(OT).hash_code());
        return objkey;
    }

    class lua_guard {
    public:
        lua_guard(lua_State* L) : m_L(L) { m_top = lua_gettop(L); }
        ~lua_guard() { lua_settop(m_L, m_top); }
        lua_guard(const lua_guard& other) = delete;
        lua_guard(lua_guard&& other) = delete;
        lua_guard& operator =(const lua_guard&) = delete;
    private:
        int m_top = 0;
        lua_State* m_L = nullptr;
    };

}
