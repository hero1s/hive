#pragma once
#include "lua_buff.h"
#include "lua_codec.h"
#include "lua_table.h"
#include "lua_class.h"

namespace luakit {
    class kit_state {
    public:
        kit_state() {
            m_L = luaL_newstate();
            luaL_openlibs(m_L);
            new_class<codec_base>();
            new_class<class_member>();
            new_class<function_wrapper>();
            new_class<slice>(
                "size", &slice::size,
                "recv", &slice::recv,
                "peek", &slice::check,
                "string", &slice::string
            );
            m_buf = new luabuf();
            lua_table luakit = new_table("luakit");
            luakit.set_function("encode", [&](lua_State* L) { return encode(L, m_buf); });
            luakit.set_function("decode", [&](lua_State* L) { return decode(L, m_buf); });
            luakit.set_function("unserialize", [&](lua_State* L) {  return unserialize(L); });
            luakit.set_function("serialize", [&](lua_State* L) { return serialize(L, m_buf); });
        }
        kit_state(lua_State* L) : m_L(L) {}

        void close() {
            lua_close(m_L);
            if (m_buf) { delete m_buf; }
            if (m_codec) { delete m_codec; }
        }

        codec_base* create_codec() {
            if (!m_codec) {
                if (!m_buf) m_buf = new luabuf();
                m_codec = new luacodec();
                m_codec->set_buff(m_buf);
            }
            return m_codec;
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
        bool call(const char* function, error_fn efn, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_global_function(m_L, function, efn, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        bool call(const char* function, error_fn efn = nullptr) {
            return call_global_function(m_L, function, efn, std::tie());
        }

        bool call(error_fn efn = nullptr) {
            return lua_call_function(m_L, efn, std::tie());
        }

        template <typename... ret_types, typename... arg_types>
        bool table_call(const char* table, const char* function, error_fn efn, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_table_function(m_L, table, function, efn, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        template <typename... ret_types, typename... arg_types>
        bool table_call(const char* table, const char* function, error_fn efn, codec_base* codec, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_table_function(m_L, table, function, efn, codec, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        bool table_call(const char* table, const char* function, error_fn efn = nullptr) {
            return call_table_function(m_L, table, function, efn, std::tie());
        }

        template <typename T, typename... ret_types, typename... arg_types>
        bool object_call(T* obj, const char* function, error_fn efn, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_object_function<T>(m_L, obj, function, efn, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        template <typename T, typename... ret_types, typename... arg_types>
        bool object_call(T* obj, const char* function, error_fn efn, codec_base* codec, std::tuple<ret_types&...>&& rets, arg_types... args) {
            return call_object_function<T>(m_L, obj, function, efn, codec, std::forward<std::tuple<ret_types&...>>(rets), std::forward<arg_types>(args)...);
        }

        template <typename T>
        bool object_call(T* obj, const char* function, error_fn efn = nullptr) {
            return call_object_function<T>(function, obj, efn, std::tie());
        }

        bool run_file(const std::string& filename, error_fn efn = nullptr) {
            return run_file(filename.c_str(), efn);
        }

        bool run_file(const char* filename, error_fn efn = nullptr) {
            lua_guard g(m_L);
            if (luaL_loadfile(m_L, filename)) {
                if (efn) {
                    efn(lua_tostring(m_L, -1));
                }
                return false;
            }
            return lua_call_function(m_L, efn, 0, 0);
        }

        bool run_script(const std::string& script, error_fn efn= nullptr) {
            return run_script(script.c_str(), efn);
        }

        bool run_script(const char* script, error_fn efn= nullptr) {
            lua_guard g(m_L);
            if (luaL_loadstring(m_L, script)) {
                if (efn) {
                    efn(lua_tostring(m_L, -1));
                }
                return false;
            }
            return lua_call_function(m_L, efn, 0, 0);
        }

        lua_table new_table(const char* name = nullptr) {
            lua_guard g(m_L);
            lua_createtable(m_L, 0, 8);
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
        luabuf* m_buf = nullptr; 
        luacodec* m_codec = nullptr;
        lua_State* m_L = nullptr;
    };

}
