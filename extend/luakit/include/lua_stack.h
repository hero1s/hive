#pragma once
#include "lua_base.h"

namespace luakit {

    template <typename T>
    T lua_to_object(lua_State* L, int idx);
    template <typename T>
    void lua_push_object(lua_State* L, T obj);

    //将lua栈顶元素转换成C++对象
    template <typename T>
    T lua_to_native(lua_State* L, int i) {
        if constexpr (std::is_same_v<T, bool>) {
            return lua_toboolean(L, i) != 0;
        }
        else if constexpr (std::is_same_v<T, std::string>) {
            size_t len;
            const char* str = lua_tolstring(L, i, &len);
            return str == nullptr ? "" : std::string(str, len);
        }
        else if constexpr (std::is_integral_v<T>) {
            return (T)lua_tointeger(L, i);
        }
        else if constexpr (std::is_floating_point_v<T>) {
            return (T)lua_tonumber(L, i);
        }
        else if constexpr (std::is_enum<T>::value) {
            return (T)lua_tonumber(L, i);
        }
        else if constexpr (std::is_pointer_v<T>) {
            using type = std::remove_volatile_t<std::remove_pointer_t<T>>;
            if constexpr (std::is_same_v<type, const char>) {
                return lua_tostring(L, i);
            }
            else {
                return lua_to_object<T>(L, i);
            }
        }
    }

    //C++对象压到lua堆顶
    template <typename T>
    int native_to_lua(lua_State* L, T v) {
        if constexpr (std::is_same_v<T, bool>) {
            lua_pushboolean(L, v);
        }
        else if constexpr (std::is_same_v<T, std::string>) {
            lua_pushlstring(L, v.c_str(), v.size());
        }
        else if constexpr (std::is_integral_v<T>) {
            lua_pushinteger(L, (lua_Integer)v);
        }
        else if constexpr (std::is_floating_point_v<T>) {
            lua_pushnumber(L, v);
        }
        else if constexpr (std::is_enum<T>::value) {
            lua_pushinteger(L, (lua_Integer)v);
        }
        else if constexpr (std::is_pointer_v<T>) {
            using type = std::remove_cv_t<std::remove_pointer_t<T>>;
            if constexpr (std::is_same_v<type, char>) {
                if (v != nullptr) {
                    lua_pushstring(L, v);
                }
                else {
                    lua_pushnil(L);
                }
            }
            else {
                lua_push_object(L, v);
            }
        }
        else {
            lua_pushnil(L);
        }
        return 1;
    }

    //template template parameters
    //std::array
    template <typename T, std::size_t N, template<typename TE, std::size_t TN> typename TTP>
    int native_to_lua(lua_State* L, TTP<T, N> v) {
        uint32_t index = 1;
        lua_createtable(L, 0, 8);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::vector/std::list/std::deque/std::forward_list
    template <template<typename, typename> class TTP, typename T>
    int native_to_lua(lua_State* L, TTP<T, std::allocator<T>> v) {
        uint32_t index = 1;
        lua_createtable(L, 0, 8);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::vector/std::list/std::deque
    template <template<typename, typename> class TTP, typename T>
    bool lua_to_native(lua_State* L, int i, TTP<T, std::allocator<T>>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.push_back(lua_to_native<T>(L, -1));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

    //std::set/std::multiset
    template <template<typename, typename, typename> class TTP, typename T>
    int native_to_lua(lua_State* L, TTP<T, std::less<T>, std::allocator<T>> v) {
        uint32_t index = 1;
        lua_createtable(L, 0, 8);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::set/std::multiset
    template <template<typename, typename, typename> class TTP, typename T>
    bool lua_to_native(lua_State* L, int i, TTP<T, std::less<T>, std::allocator<T>>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(lua_to_native<T>(L, -1));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

   //std::unordered_set/std::unordered_multiset
    template <template<typename, typename, typename, typename> class TTP, typename T>
    int native_to_lua(lua_State* L, TTP<T, std::hash<T>, std::equal_to<T>, std::allocator<T>> v) {
         uint32_t index = 1;
        lua_createtable(L, 0, 8);
         for (auto item : v) {
             native_to_lua<T>(L, item);
             lua_seti(L, -2, index++);
         }
         return 1;
     }

    //std::unordered_set/std::unordered_multiset
    template <template<typename, typename, typename, typename> class TTP, typename T>
    bool lua_to_native(lua_State* L, int i, TTP<T, std::hash<T>, std::equal_to<T>, std::allocator<T>>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(lua_to_native<T>(L, -1));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

    // //std::map/std::multimap
    template <template<typename, typename, typename, typename> class TTP, typename K, typename V>
    int native_to_lua(lua_State* L, TTP<K, V, std::less<K>, std::allocator<std::pair<const K, V>>> v) {
        lua_createtable(L, 0, 8);
        for (auto item : v) {
            native_to_lua<K>(L, item.first);
            native_to_lua<V>(L, item.second);
            lua_settable(L, -3);
        }
        return 1;
    }

    //std::map/std::multimap
    template <template<typename, typename, typename, typename> class TTP, typename K, typename V>
    bool lua_to_native(lua_State* L, int i, TTP<K, V, std::less<K>, std::allocator<std::pair<const K, V>>>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(std::make_pair(lua_to_native<K>(L, -2), lua_to_native<V>(L, -1)));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

    //std::unordered_map/std::unordered_multimap
    template <template<typename, typename, typename, typename, typename> class TTP, typename K, typename V>
    int native_to_lua(lua_State* L, TTP<K, V, std::hash<K>, std::equal_to<K>, std::allocator< std::pair<const K, V>>> v) {
        lua_createtable(L, 0, 8);
        for (auto item : v) {
            native_to_lua<K>(L, item.first);
            native_to_lua<V>(L, item.second);
            lua_settable(L, -3);
        }
        return 1;
    }

    //std::unordered_map/std::unordered_multimap
    template <template<typename, typename, typename, typename, typename> class TTP, typename K, typename V>
    bool lua_to_native(lua_State* L, int i, TTP<K, V, std::hash<K>, std::equal_to<K>, std::allocator< std::pair<const K, V>>>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(std::make_pair(lua_to_native<K>(L, -2), lua_to_native<V>(L, -1)));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

    template <typename T>
    void lua_push_object(lua_State* L, T obj) {
        if (obj == nullptr) {
            lua_pushnil(L);
            return;
        }

        lua_getfield(L, LUA_REGISTRYINDEX, "__objects__");
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            lua_createtable(L, 0, 128);
            lua_createtable(L, 0, 4);
            lua_pushstring(L, "v");
            lua_setfield(L, -2, "__mode");
            lua_setmetatable(L, -2);
            lua_pushvalue(L, -1);
            lua_setfield(L, LUA_REGISTRYINDEX, "__objects__");
        }

        // stack: __objects__
        size_t pkey = lua_get_object_key(obj);
        if (lua_geti(L, -1, pkey) != LUA_TTABLE) {
            lua_pop(L, 1);
            lua_createtable(L, 0, 4);
            lua_pushlightuserdata(L, obj);
            lua_setfield(L, -2, "__pointer__");
            // stack: __objects__, table
            const char* meta_name = lua_get_meta_name<T>();
            luaL_getmetatable(L, meta_name);
            if (lua_isnil(L, -1)) {
                lua_pop(L, 3);
                lua_pushlightuserdata(L, obj);
                return;
            }
            // stack: __objects__, table, metatab
            lua_setmetatable(L, -2);
            lua_pushvalue(L, -1);
            // stack: __objects__, table, table
            lua_seti(L, -3, pkey);
        }
        // stack: __objects__, table
        lua_remove(L, -2);
    }

    template <typename T>
    void lua_detach_object(lua_State* L, T obj) {
        if (obj == nullptr)
            return;
        lua_getfield(L, LUA_REGISTRYINDEX, "__objects__");
        if (!lua_istable(L, -1)) {
            lua_pop(L, 1);
            return;
        }
        // stack: __objects__
        size_t pkey = lua_get_object_key(obj);
        if (lua_geti(L, -1, pkey) != LUA_TTABLE) {
            lua_pop(L, 2);
            return;
        }
        // stack: __objects__, table
        lua_pushnil(L);
        lua_setfield(L, -2, "__pointer__");
        // stack: __objects__, table
        lua_pushnil(L);
        lua_seti(L, -3, pkey);
        lua_pop(L, 2);
    }

    template <typename T>
    T lua_to_object(lua_State* L, int idx) {
        if (lua_istable(L, idx)) {
            lua_getfield(L, idx, "__pointer__");
            T obj = (T)lua_touserdata(L, -1);
            lua_pop(L, 1);
            return obj;
        }
        if (lua_isuserdata(L, idx)) {
            return (T)lua_touserdata(L, idx);
        }
        return nullptr;
    }

    template<typename... arg_types>
    void native_to_lua_mutil(lua_State* L, arg_types&&... args) {
        int _[] = { 0, (native_to_lua(L, args), 0)... };
    }

    template<size_t... integers, typename... var_types>
    void lua_to_native_mutil(lua_State* L, std::tuple<var_types&...>& vars, std::index_sequence<integers...>&&) {
        int _[] = { 0, (std::get<integers>(vars) = lua_to_native<var_types>(L, (int)integers - (int)sizeof...(integers)), 0)... };
    }
}
