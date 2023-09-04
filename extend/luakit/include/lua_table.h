#pragma once
#include "lua_reference.h"

namespace luakit {

    class lua_table : public reference {
    public:
        lua_table(lua_State* L) : reference(L) {}

        template<typename RET, typename KEY>
        RET get(KEY key) {
            lua_guard g(m_L);
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            native_to_lua(m_L, key);
            lua_gettable(m_L, -2);
            return lua_to_native<RET>(m_L, -1);
        }

        template<typename T, typename KEY>
        void set(KEY key, T value) {
            lua_guard g(m_L);
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            native_to_lua(m_L, key);
            native_to_lua(m_L, value);
            lua_settable(m_L, -3);
        }

        template <typename T, typename KEY, typename... arg_types>
        void set(KEY key, T value, arg_types&&... args) {
            set(key, value);
            set(std::forward<arg_types>(args)...);
        }

        template<typename T>
        void set_function(const char* function, T func) {
            lua_guard g(m_L);
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            lua_pushstring(m_L, function);
            lua_push_function(m_L, func);
            lua_settable(m_L, -3);
        }

        bool get_function(const char* function) {
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            lua_getfield(m_L, -1, function);
            lua_remove(m_L, -2);
            return lua_isfunction(m_L, -1);
        }

        template <typename... ret_types, typename... arg_types>
        bool call(const char* function, error_fn efn, std::tuple<ret_types&...>&& rets, arg_types... args) {
            if (!get_function(function)) return false;
            return lua_call_function(m_L, efn, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        bool call(const char* function, error_fn efn = nullptr) {
            if (!get_function(function)) return false;
            return lua_call_function(m_L, efn, std::tie());
        }

        bool call(error_fn efn = nullptr) {
            return lua_call_function(m_L, efn, std::tie());
        }

        void create_with() {}

        template <typename... arg_types>
        void create_with(arg_types... args) {
            static_assert(sizeof...(args) % 2 == 0, "You must have an even number of arguments for a key, value ... list.");
            set(std::forward<arg_types>(args)...);
        }

        template <typename... enum_value>
        lua_table new_enum(const char* name, enum_value... args) {
            lua_guard g(m_L);
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            lua_createtable(m_L, 0, 8);
            lua_pushstring(m_L, name);
            lua_pushvalue(m_L, -2);
            lua_settable(m_L, -4);
            auto table = lua_table(m_L);
            table.create_with(std::forward<enum_value>(args)...);
            return table;
        }
    };

    template <>
    inline int native_to_lua(lua_State* L, lua_table tb) {
        return tb.push_stack();
    }

    template <>
    inline lua_table lua_to_native(lua_State* L, int i) {
        lua_guard g(L);
        lua_pushvalue(L, i);
        return lua_table(L);
    }
}
