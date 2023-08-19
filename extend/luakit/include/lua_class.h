#pragma once
#include "lua_function.h"

namespace luakit {

    template<typename>
    struct member_traits {};
    template<typename class_type, typename member_type>
    struct member_traits<member_type class_type::*> {
        using type = member_type;
    };

    template<typename T>
    struct has_member_gc {
        template<typename U> static auto check_gc(int) -> decltype(std::declval<U>().__gc(), std::true_type());
        template<typename U> static std::false_type check_gc(...);
        enum { value = std::is_same<decltype(check_gc<T>(0)), std::true_type>::value };
    };

    inline int lua_object_bridge(lua_State* L) {
        void* obj = lua_touserdata(L, lua_upvalueindex(1));
        object_function* func = (object_function*)lua_touserdata(L, lua_upvalueindex(2));
        if (obj != nullptr && func != nullptr) {
            return (*func)(obj, L);
        }
        return 0;
    }

    //类成员（变量、函数）包装器
    using member_wrapper = std::function<void(lua_State*, void*)>;
    //C++函数导出lua辅助器
    struct lua_export_helper {
        template <typename T, typename MT>
        static member_wrapper getter(MT T::* member) {
            return [=](lua_State* L, void* obj) {
                native_to_lua<MT>(L, ((T*)obj)->*member);
            };
        }
        template <typename T, typename MT>
        static member_wrapper setter(MT T::* member) {
            return [=](lua_State* L, void* obj) {
                ((T*)obj)->*member = lua_to_native<MT>(L, -1);
            };
        }
        //类成员函数的get/set辅助器
        template <typename return_type, typename T, typename... arg_types>
        static member_wrapper getter(return_type(T::* func)(arg_types...)) {
            return [adapter = lua_adapter(func)](lua_State* L, void* obj) mutable {
                lua_pushlightuserdata(L, obj);
                lua_pushlightuserdata(L, &adapter);
                lua_pushcclosure(L, lua_object_bridge, 2);
            };
        }
        //类const成员函数的get/set辅助器
        template <typename return_type, typename T, typename... arg_types>
        static member_wrapper getter(return_type(T::* func)(arg_types...) const) {
            return [adapter = lua_adapter(func)](lua_State* L, void* obj) mutable {
                lua_pushlightuserdata(L, obj);
                lua_pushlightuserdata(L, &adapter);
                lua_pushcclosure(L, lua_object_bridge, 2);
            };
        }
    };

    //类成员元素的声
    struct class_member {
        bool is_function = false;
        member_wrapper getter = nullptr;
        member_wrapper setter = nullptr;
    };

    template <typename T>
    int lua_class_index(lua_State* L) {
        T* obj = lua_to_object<T*>(L, 1);
        if (!obj) {
            lua_pushnil(L);
            return 1;
        }

        const char* key = lua_tostring(L, 2);
        const char* meta_name = lua_get_meta_name<T>();
        if (!key || !meta_name) {
            lua_pushnil(L);
            return 1;
        }
        luaL_getmetatable(L, meta_name);
        lua_pushstring(L, key);
        lua_rawget(L, -2);

        auto member = lua_to_object<class_member*>(L, -1);
        lua_pop(L, 2);
        if (!member) {
            lua_pushnil(L);
            return 1;
        }
        member->getter(L, obj);
        return 1;
    }

    template <typename T>
    int lua_class_newindex(lua_State* L) {
        T* obj = lua_to_object<T*>(L, 1);
        if (!obj) return 0;

        const char* key = lua_tostring(L, 2);
        const char* meta_name = lua_get_meta_name<T>();
        if (!key || !meta_name) return 0;

        luaL_getmetatable(L, meta_name);
        lua_pushstring(L, key);
        lua_rawget(L, -2);

        auto member = lua_to_object<class_member*>(L, -1);
        lua_pop(L, 2);

        if (!member || member->is_function) {
            lua_rawset(L, -3);
            return 0;
        }
        if (member->setter) {
            member->setter(L, obj);
        }
        return 0;
    }

    template <typename T>
    int lua_class_gc(lua_State* L) {
        T* obj = lua_to_object<T*>(L, 1);
        if (!obj) return 0;
        if constexpr (has_member_gc<T>::value) {
            obj->__gc();
        }
        else {
            delete obj;
        }
        return 0;
    }

    //class memeber wrapper
    //-------------------------------------------------------------------------------
    inline void lua_wrap_member(lua_State* L) {}

    template <typename MT>
    void lua_wrap_member(lua_State* L, const char* name, MT member) {
        lua_pushstring(L, name);
        if constexpr (std::is_function<typename member_traits<decltype(member)>::type>::value) {
            lua_push_object(L, new class_member({ true, lua_export_helper::getter(member), nullptr }));
        }
        else {
            lua_push_object(L, new class_member({ false, lua_export_helper::getter(member), lua_export_helper::setter(member) }));
        }
        lua_rawset(L, -3);
    }

    template <typename MT, typename... arg_types>
    void lua_wrap_member(lua_State* L, const char* name, MT member, arg_types&&... args) {
        lua_wrap_member(L, name, member);
        lua_wrap_member(L, std::forward<arg_types>(args)...);
    }

    template <typename T, typename... arg_types>
    void lua_wrap_class(lua_State* L, arg_types... args) {
        lua_guard g(L);
        const char* meta_name = lua_get_meta_name<T>();
        luaL_getmetatable(L, meta_name);
        if (lua_isnil(L, -1)) {
            //创建类元表以及基础元方法
            luaL_Reg meta[] = {
                {"__gc", &lua_class_gc<T>},
                {"__index", &lua_class_index<T>},
                {"__newindex", &lua_class_newindex<T>},
                {NULL, NULL}
            };
            lua_pop(L, 1);
            luaL_newmetatable(L, meta_name);
            luaL_setfuncs(L, meta, 0);
            //注册类成员
            static_assert(sizeof...(args) % 2 == 0, "You must have an even number of arguments for a key, value ... list.");
            lua_wrap_member(L, std::forward<arg_types>(args)...);
        }
    }

}
