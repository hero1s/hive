#pragma once
#include "lua_stack.h"

namespace luakit {

    //辅助识别lambda函数
    template <typename F>
    struct function_traits : public function_traits<decltype(&F::operator())> {};
    template <typename return_type, typename class_type, typename... arg_types>
    struct function_traits<return_type(class_type::*)(arg_types...) const> {
        typedef std::function<return_type(arg_types...)> func;
    };
    template <typename F>
    typename function_traits<F>::func to_function(F& lambda) {
        return typename function_traits<F>::func(lambda);
    }

    //定义全局函数和类函数
    using global_function = std::function<int(lua_State*)>;
    using object_function = std::function<int(void*, lua_State*)>;

    //call global function
    //-------------------------------------------------------------------------------
    //辅助调用C++全局函数(normal function)
    template<size_t... integers, typename return_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, return_type(*func)(arg_types...), std::index_sequence<integers...>&&) {
        return (*func)(lua_to_native<arg_types>(L, integers + 1)...);
    }

    template<size_t... integers, typename return_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, return_type(*func)(lua_State*, arg_types...), std::index_sequence<integers...>&&) {
        return (*func)(L, lua_to_native<arg_types>(L, integers + 1)...);
    }

    //辅助调用C++全局函数(std::function)
    template<size_t... integers, typename return_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, std::function<return_type(arg_types...)> func, std::index_sequence<integers...>&&) {
        return func(lua_to_native<arg_types>(L, integers + 1)...);
    }
    
    template<size_t... integers, typename return_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, std::function<return_type(lua_State*, arg_types...)> func, std::index_sequence<integers...>&&) {
        return func(L, lua_to_native<arg_types>(L, integers + 1)...);
    }

    //call object function
    //-------------------------------------------------------------------------------
    //辅助调用C++类函数
    template<size_t... integers, typename return_type, typename class_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, class_type* obj, return_type(class_type::* func)(arg_types...), std::index_sequence<integers...>&&) {
        return (obj->*func)(lua_to_native<arg_types>(L, integers + 1)...);
    }

    template<size_t... integers, typename return_type, typename class_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, class_type* obj, return_type(class_type::* func)(arg_types...) const, std::index_sequence<integers...>&&) {
        return (obj->*func)(lua_to_native<arg_types>(L, integers + 1)...);
    }

    template<size_t... integers, typename return_type, typename class_type, typename... arg_types>
    inline return_type call_helper(lua_State* L, class_type* obj, return_type(class_type::* func)(lua_State*, arg_types...), std::index_sequence<integers...>&&) {
        return (obj->*func)(L, lua_to_native<arg_types>(L, integers + 1)...);
    }

    //adapter global function
    //-------------------------------------------------------------------------------
    //适配有返回值的C++全局函数
    template <typename return_type, typename... arg_types>
    inline global_function lua_adapter(return_type(*func)(arg_types...)) {
        return [=](lua_State* L) {
            return native_to_lua(L, call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }

    //适配无返回值的全局函数
    template <typename... arg_types>
    inline global_function lua_adapter(void(*func)(arg_types...)) {
        return [=](lua_State* L) {
            call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>());
            return 0;
        };
    }

    //适配特殊lua的CAPI编写的全局函数
    template <typename... arg_types>
    inline global_function lua_adapter(int (*func)(lua_State*, arg_types...)) {
        return [=](lua_State* L) {
            return call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>());
        };
    }
    template <typename return_type, typename... arg_types>
    inline global_function lua_adapter(return_type(*func)(lua_State*, arg_types...)) {
        return [=](lua_State* L) {
            return native_to_lua(L, call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }

    //适配有返回值std::function全局函数
    template <typename return_type, typename... arg_types>
    inline global_function lua_adapter(std::function<return_type(arg_types...)> func) {
        return [=](lua_State* L) {
            return native_to_lua(L, call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }
    
    //适配无返回值std::function全局函数
    template <typename... arg_types>
    inline global_function lua_adapter(std::function<void(arg_types...)> func) {
        return [=](lua_State* L) {
            call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>());
            return 0;
        };
    }

    //适配特殊lua的CAPI编写std::function全局函数
    template <typename... arg_types>
    inline global_function lua_adapter(std::function<int(lua_State*, arg_types...)> func) {
        return [=](lua_State* L) {
            return call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>());
        };
    }
    template <typename return_type, typename... arg_types>
    inline global_function lua_adapter(std::function<return_type(lua_State*, arg_types...)> func) {
        return [=](lua_State* L) {
            return native_to_lua(L, call_helper(L, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }

    //适配使用lua的CAPI编写的全局函数
    template <>
    inline global_function lua_adapter(int(*func)(lua_State* L)) {
        return func;
    }

    //适配C++ lambda全局函数
    template <typename L>
    inline global_function lua_adapter(L& lambda) {
        return lua_adapter(to_function(lambda));
    }

    //object function
    //-------------------------------------------------------------------------------
    //适配有返回值的C++类函数/const类函数
    template <typename return_type, typename T, typename... arg_types>
    inline object_function lua_adapter(return_type(T::* func)(arg_types...)) {
        return [=](void* obj, lua_State* L) {
            return native_to_lua(L, call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }
    template <typename return_type, typename T, typename... arg_types>
    inline object_function lua_adapter(return_type(T::* func)(arg_types...) const) {
        return [=](void* obj, lua_State* L) {
            return native_to_lua(L, call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }

    //适配无返回值的C++类函数/const类函数
    template <typename T, typename... arg_types>
    inline object_function lua_adapter(void(T::* func)(arg_types...)) {
        return [=](void* obj, lua_State* L) {
            call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>());
            return 0;
        };
    }
    template <typename T, typename... arg_types>
    inline object_function lua_adapter(void(T::* func)(arg_types...) const) {
        return [=](void* obj, lua_State* L) {
            call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>());
            return 0;
        };
    }

    //适配特殊lua的CAPI编写的C++类函数
    template <typename return_type, typename T, typename... arg_types>
    inline object_function lua_adapter(return_type(T::* func)(lua_State*, arg_types...)) {
        return [=](void* obj, lua_State* L) {
            return native_to_lua(L, call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>()));
        };
    }
    template <typename T, typename... arg_types>
    inline object_function lua_adapter(int(T::* func)(lua_State*, arg_types...)) {
        return [=](void* obj, lua_State* L) {
            return call_helper(L, (T*)obj, func, std::make_index_sequence<sizeof...(arg_types)>());
        };
    }
    template <typename T>
    inline object_function lua_adapter(int(T::* func)(lua_State* L)) {
        return [=](void* obj, lua_State* L) {
            return (((T*)obj)->*func)(L);
        };
    }

    //push function
    //-------------------------------------------------------------------------------
    //全局函数包装器
    struct function_wrapper final {
        function_wrapper(const global_function& func) : m_func(func) {}
        global_function m_func;
    };

    //全局函数闭包
    inline int lua_global_bridge(lua_State* L) {
        auto* wapper = lua_to_object<function_wrapper*>(L, lua_upvalueindex(1));
        return wapper ? wapper->m_func(L) : 0;
    }

    inline void lua_push_function(lua_State* L, global_function func) {
        lua_push_object(L, new function_wrapper(func));
        lua_pushcclosure(L, lua_global_bridge, 1);
    }

    inline void lua_push_function(lua_State* L, lua_CFunction func) {
        lua_pushcfunction(L, func);
    }

    template <typename T>
    inline void lua_push_function(lua_State* L, T func) {
        lua_push_function(L, lua_adapter(func));
    }

    //get function
    //-------------------------------------------------------------------------------
    inline bool get_global_function(lua_State* L, const char* function) {
        lua_getglobal(L, function);
        return lua_isfunction(L, -1);
    }

    inline bool get_table_function(lua_State* L, const char* table, const char* function) {
        lua_getglobal(L, table);
        if (!lua_istable(L, -1)) return false;
        lua_getfield(L, -1, function);
        lua_remove(L, -2);
        return lua_isfunction(L, -1);
    }

    template <typename T>
    bool get_object_function(lua_State* L, T* object, const char* function) {
        lua_push_object(L, object);
        if (!lua_istable(L, -1)) return false;
        lua_getfield(L, -1, function);
        lua_remove(L, -2);
        return lua_isfunction(L, -1);
    }

    //call function
    //-------------------------------------------------------------------------------
    static bool lua_call_function(lua_State* L, exception_handler handler, int arg_count, int ret_count) {
        int func_idx = lua_gettop(L) - arg_count;
        if (func_idx <= 0 || !lua_isfunction(L, func_idx))
            return false;

        lua_getglobal(L, "debug");
        lua_getfield(L, -1, "traceback");
        lua_remove(L, -2);  // remove 'debug'

        lua_insert(L, func_idx);
        if (lua_pcall(L, arg_count, ret_count, func_idx)) {
            if (handler != nullptr) {
                handler(lua_tostring(L, -1));
            }
            lua_pop(L, 2);
            return false;
        }
        lua_remove(L, -ret_count - 1);  // remove 'traceback'
        return true;
    }

    template <typename... ret_types, typename... arg_types>
    bool lua_call_function(lua_State* L, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
        native_to_lua_mutil(L, std::forward<arg_types>(args)...);
        if (!lua_call_function(L, handler, sizeof...(arg_types), sizeof...(ret_types)))
            return false;
        lua_to_native_mutil(L, rets, std::make_index_sequence<sizeof...(ret_types)>());
        lua_pop(L, (int)sizeof...(ret_types));
        return true;
    }

    template <typename... ret_types, typename... arg_types>
    bool call_global_function (lua_State* L, const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
        if (!get_global_function(L, function)) return false;
        return lua_call_function(L, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
    }

    template <typename... ret_types, typename... arg_types>
    bool call_table_function(lua_State* L, const char* table, const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
        if (!get_table_function(L, table, function)) return false;
        return lua_call_function(L, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
    }

    template <typename T, typename... ret_types, typename... arg_types>
    bool call_object_function(lua_State* L, T* o, const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
        if (!get_object_function(L, o, function)) return false;
        return lua_call_function(L, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
    }

    template <typename T>
    int args_return(lua_State* L, T v) {
        return native_to_lua(L, std::move(v));
    }

    template<typename... arg_types>
    static int variadic_return(lua_State* L, arg_types... args) {
        int _[] = { args_return<arg_types>(L, std::move(args))... };
        return sizeof...(arg_types);
    }
}
