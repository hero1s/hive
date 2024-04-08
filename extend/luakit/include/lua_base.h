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

    class lua_exception : public std::logic_error {
    public:
        template <class... Args>
        explicit lua_exception(const char* fmt, Args&&... args) : std::logic_error(format(fmt, std::forward<Args>(args)...)) {}

    protected:
        template <class... Args>
        std::string format(const char* fmt, Args&&... args) {
            int buf_size = std::snprintf(nullptr, 0, fmt, std::forward<Args>(args)...) + 1;
            if (buf_size < 0) return "unknown error!";
            std::unique_ptr<char[]> buf = std::make_unique<char[]>(buf_size);
            std::snprintf(buf.get(), buf_size, fmt, std::forward<Args>(args)...);
            return std::string(buf.get(), buf_size - 1);
        }
    };

}
