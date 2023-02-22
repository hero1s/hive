#pragma once
#include "lua_buff.h"
#include "lua_table.h"
#include "lua_class.h"

namespace luakit {

    class kit_state {
    public:
        kit_state() {
            m_L = luaL_newstate();
            luaL_openlibs(m_L);
            new_class<class_member>();
            new_class<function_wrapper>();
            new_class<slice>(
                "size", &slice::size,
                "read", &slice::read,
                "peek", &slice::check,
                "string", &slice::string,
                "contents", &slice::contents
            );
        }
        kit_state(lua_State* L) : m_L(L) {}

        void close() {
            lua_close(m_L);
        }

        template<typename T>
        void set(const char* name, T obj) {
            native_to_lua(m_L, obj);
            lua_setglobal(m_L, name);
        }

        template<typename T>
        T get(const char* name) {
            lua_guard g(m_L);
            lua_getglobal(m_L, name);
            return lua_to_native<T>(m_L, -1);
        }

        template <typename F>
        void set_function(const char* function, F func) {
            lua_push_function(m_L, func);
            lua_setglobal(m_L, function);
        }

        bool get_function(const char* function) {
            get_global_function(m_L, function);
            return lua_isfunction(m_L, -1);
        }

        template <typename... ret_types, typename... arg_types>
        bool call(const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_global_function(m_L, function, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        bool call(const char* function, exception_handler handler = nullptr) {
            return call_global_function(m_L, function, handler, std::tie());
        }

        bool call(exception_handler handler = nullptr) {
            return lua_call_function(m_L, handler, std::tie());
        }

        template <typename... ret_types, typename... arg_types>
        bool table_call(const char* table, const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_table_function(m_L, table, function, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        bool table_call(const char* table, const char* function, exception_handler handler = nullptr) {
            return call_table_function(m_L, table, function, handler, std::tie());
        }

        template <typename T, typename... ret_types, typename... arg_types>
        bool object_call(T* obj, const char* function, exception_handler handler, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_object_function<T>(m_L, obj, function, handler, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        template <typename T>
        bool object_call(T* obj, const char* function, exception_handler handler = nullptr) {
            return call_object_function<T>(function, obj, handler, std::tie());
        }
        
        bool run_file(const std::string& filename, exception_handler handler = nullptr) {
            return run_file(filename.c_str(), handler);
        }
        
        bool run_file(const char* filename, exception_handler handler = nullptr) {
            lua_guard g(m_L);
            if (luaL_loadfile(m_L, filename)) {
                if (handler) {
                    handler(lua_tostring(m_L, -1));
                }
                return false;
            }
            return lua_call_function(m_L, handler, 0, 0);
        }

        bool run_script(const std::string& script, exception_handler handler = nullptr) {
            return run_script(script.c_str(), handler);
        }

        bool run_script(const char* script, exception_handler handler = nullptr) {
            lua_guard g(m_L);
            if (luaL_loadstring(m_L, script)) {
                if (handler) {
                    handler(lua_tostring(m_L, -1));
                }
                return false;
            }
            return lua_call_function(m_L, handler, 0, 0);
        }

        lua_table new_table(const char* name = nullptr) {
            lua_guard g(m_L);
            lua_newtable(m_L);
            if (name) {
                lua_pushvalue(m_L, -1);
                lua_setglobal(m_L, name);
            }
            return lua_table(m_L);
        }

        template <typename... arg_types>
        lua_table new_table(const char* name, arg_types... args) {
            lua_table table = new_table(name);
            table.create_with(std::forward<arg_types>(args)...);
            return table;
        }

        template <typename... enum_value>
        lua_table new_enum(const char* name, enum_value... args) {
            lua_table table = new_table(name);
            table.create_with(std::forward<enum_value>(args)...);
            return table;
        }

        template<typename T, typename... arg_types>
        void new_class(arg_types... args) {
            lua_wrap_class<T>(m_L, std::forward<arg_types>(args)...);
        }

        template <typename T>
        int push(T v) {
            return native_to_lua(m_L, std::move(v));
        }

        template <typename T>
        reference new_reference(T v) {
            lua_guard g(m_L);
            native_to_lua(m_L, std::move(v));
            return reference(m_L);
        }

        lua_State* L() { 
            return m_L;
        }

    protected:
        lua_State* m_L = nullptr;
    };

}
