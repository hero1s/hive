#pragma once

#include <set>
#include <map>
#include <list>
#include <tuple>
#include <string>
#include <vector>
#include <memory>
#include <utility>
#include <cstdint>
#include <stdexcept>
#include <functional>
#include <type_traits>
#include <string.h>
#include <unordered_map>

extern "C"
{
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

namespace luakit {

    static thread_local std::unordered_map<size_t, std::string> meta_name_cache;
    //错误函数
    using error_fn = std::function<void(std::string_view err)>;

    template<typename T>
    const char* lua_get_meta_name() {
        thread_local char meta_name[128];
        using OT = std::remove_cv_t<std::remove_pointer_t<T>>;
        auto type_hash = typeid(OT).hash_code();
        auto it = meta_name_cache.find(type_hash);
        if (it != meta_name_cache.end()) {
            return it->second.c_str();
        }
        snprintf(meta_name, 128, "__lua_class_meta_%zu__", type_hash);
        meta_name_cache[type_hash] = meta_name;
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

    inline bool is_lua_array(lua_State* L, int index, bool emy_as_arr = false) {
        if (lua_type(L, index) != LUA_TTABLE) return false;
        size_t raw_len = lua_rawlen(L, index);
        if (raw_len == 0 && !emy_as_arr) return false;
        index = lua_absindex(L, index);
        lua_guard g(L);
        lua_pushnil(L);
        size_t curlen = 0;
        while (lua_next(L, index) != 0) {
            if (!lua_isinteger(L, -2)) return false;
            size_t key = lua_tointeger(L, -2);
            if (key <= 0 || key > raw_len) return false;
            lua_pop(L, 1);
            curlen++;
        }
        return curlen == raw_len;
    }

    class lua_exception : public std::logic_error {
    public:
        template <class... Args>
        explicit lua_exception(const char* fmt, Args&&... args) : std::logic_error(format(fmt, std::forward<Args>(args)...)) {}

    protected:
        template <class... Args>
        std::string format(const char* fmt, Args&&... args) {
            int required_size = std::snprintf(nullptr, 0, fmt, std::forward<Args>(args)...);
            if (required_size < 0) return "unknown error!";
            std::string result;
            result.reserve(required_size + 1);
            char* buffer = &result[0];
            int actual_size = std::snprintf(buffer, required_size + 1, fmt, std::forward<Args>(args)...);
            if (actual_size < 0 || actual_size > required_size) {
                return "format error: snprintf reported an unexpected result";
            }
            return result;
        }
    };

}
