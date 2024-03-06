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
#include <string.h>

extern "C"
{
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

namespace luakit {

#define MAX_LUA_META_KEY 128

    //错误函数
    using error_fn = std::function<void(std::string_view err)>;

    template<typename T>
    const char* lua_get_meta_name() {
        thread_local char meta_name[MAX_LUA_META_KEY];
        using OT = std::remove_cv_t<std::remove_pointer_t<T>>;
        snprintf(meta_name, MAX_LUA_META_KEY, "__lua_class_meta_%zu__", typeid(OT).hash_code());
        return meta_name;
    }

    inline size_t lua_get_object_key(void* obj) {
        return (size_t)obj;
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
