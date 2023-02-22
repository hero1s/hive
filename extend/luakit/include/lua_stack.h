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

    //std::array
    template <typename T, std::size_t N, template<typename TE, std::size_t TN> typename TTP>
    int native_to_lua(lua_State* L, TTP<T, N> v) {
        uint32_t index = 1;
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::vector/std::list/std::deque/std::forward_list
    template <typename T, template<typename TE, typename A = std::allocator<TE>> typename TTP>
    int native_to_lua(lua_State* L, TTP<T> v) {
        uint32_t index = 1;
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::vector/std::list/std::deque
    template <typename T, template<typename TE, typename A = std::allocator<TE>> typename TTP>
    bool lua_to_native(lua_State* L, int i, TTP<T>& ttp) {
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
    template <typename T, template<typename TE, typename C = std::less<TE>, typename A = std::allocator<TE>> typename TTP>
    int native_to_lua(lua_State* L, TTP<T> v) {
        uint32_t index = 1;
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::set/std::multiset
    template <typename T, template<typename TE, typename C = std::less<TE>, typename A = std::allocator<TE>> typename TTP>
    bool lua_to_native(lua_State* L, int i, TTP<T>& ttp) {
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
    template <typename T, template<typename TE, typename H = std::hash<TE>, typename E = std::equal_to<TE>, typename A = std::allocator<TE>> typename TTP>
    int native_to_lua(lua_State* L, TTP<T> v) {
        uint32_t index = 1;
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<T>(L, item);
            lua_seti(L, -2, index++);
        }
        return 1;
    }

    //std::unordered_set/std::unordered_multiset
    template <typename T, template<typename TE, typename H = std::hash<TE>, typename E = std::equal_to<TE>, typename A = std::allocator<TE>> typename TTP>
    bool lua_to_native(lua_State* L, int i, TTP<T>& ttp) {
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

    //std::map/std::multimap
    template <typename T, typename K, template<typename TK, typename TV, typename C = std::less<TK>, typename A = std::allocator<std::pair<const TK, TV>>> typename TTP>
    int native_to_lua(lua_State* L, TTP<K, T> v) {
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<K>(L, item.first);
            native_to_lua<T>(L, item.second);
            lua_settable(L, -3);
        }
        return 1;
    }

    //std::map/std::multimap
    template <typename T, typename K, template<typename TK, typename TV, typename C = std::less<TK>, typename A = std::allocator<std::pair<const TK, TV>>> typename TTP>
    bool lua_to_native(lua_State* L, int i, TTP<K, T>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(std::make_pair(lua_to_native<K>(L, -2), lua_to_native<T>(L, -1)));
                lua_pop(L, 1);
            }
            return true;
        }
        return false;
    }

    //std::unordered_map/std::unordered_multimap
    template <typename T, typename K, template<typename TK, typename TV, typename H = std::hash<TK>, typename E = std::equal_to<TK>, typename A = std::allocator<std::pair<const TK, TV>>> typename TTP>
    int native_to_lua(lua_State* L, TTP<K, T> v) {
        lua_newtable(L);
        for (auto item : v) {
            native_to_lua<K>(L, item.first);
            native_to_lua<T>(L, item.second);
            lua_settable(L, -3);
        }
        return 1;
    }

    //std::unordered_map/std::unordered_multimap
    template <typename T, typename K, template<typename TK, typename TV, typename H = std::hash<TK>, typename E = std::equal_to<TK>, typename A = std::allocator<std::pair<const TK, TV>>> typename TTP>
    bool lua_to_native(lua_State* L, int i, TTP<K, T>& ttp) {
        lua_guard g(L);
        if (lua_istable(L, i)) {
            i = lua_absindex(L, i);
            lua_pushnil(L);
            while (lua_next(L, i) != 0) {
                ttp.insert(std::make_pair(lua_to_native<K>(L, -2), lua_to_native<T>(L, -1)));
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

        const char* meta_name = lua_get_meta_name<T>();
        luaL_getmetatable(L, meta_name);
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            lua_pushlightuserdata(L, obj);
            return;
        }

        // stack: metatab
        lua_getfield(L, LUA_REGISTRYINDEX, "__objects__");
        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);
            lua_newtable(L);

            lua_newtable(L);
            lua_pushstring(L, "v");
            lua_setfield(L, -2, "__mode");
            lua_setmetatable(L, -2);

            lua_pushvalue(L, -1);
            lua_setfield(L, LUA_REGISTRYINDEX, "__objects__");
        }

        // stack: metatab, __objects__
        const char* pkey = lua_get_object_key<T>(obj);
        if (lua_getfield(L, -1, pkey) != LUA_TTABLE) {
            lua_pop(L, 1);
            lua_newtable(L);
            lua_pushstring(L, "__pointer__");
            lua_pushlightuserdata(L, obj);
            lua_rawset(L, -3);

            // stack: metatab, __objects__, tab 
            lua_pushvalue(L, -3);
            lua_setmetatable(L, -2);

            lua_pushvalue(L, -1);
            lua_setfield(L, -3, pkey);
        }
        // stack: metatab, __objects__, tab 
        lua_replace(L, -3);
        lua_pop(L, 1);
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
        const char* pkey = lua_get_object_key<T>(obj);
        if (lua_getfield(L, -1, pkey) != LUA_TTABLE) {
            lua_pop(L, 2);
            return;
        }

        // stack: __objects__, __shadow_object__
        lua_pushstring(L, "__pointer__");
        lua_pushnil(L);
        lua_rawset(L, -3);

        lua_pushnil(L);
        lua_rawsetp(L, -3, obj);
        lua_pop(L, 2);
    }

    template <typename T>
    T lua_to_object(lua_State* L, int idx) {
        if (lua_isuserdata(L, idx)) {
            return (T)lua_touserdata(L, idx);
        }
        T obj = nullptr;
        if (lua_istable(L, idx)) {
            idx = lua_absindex(L, idx);
            lua_pushstring(L, "__pointer__");
            lua_rawget(L, idx);
            obj = (T)lua_touserdata(L, -1);
            lua_pop(L, 1);
        }
        return obj;
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
