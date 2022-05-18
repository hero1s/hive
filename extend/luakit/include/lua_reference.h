#pragma once
#include "lua_function.h"

namespace luakit {
    //reference
    struct reference {
    public:
        reference(lua_State* L) : m_L(L) {
            m_index = luaL_ref(m_L, LUA_REGISTRYINDEX);
        }
        reference(const reference& ref) noexcept {
            m_L = ref.m_L;
            lua_guard g(m_L);
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, ref.m_index);
            m_index = luaL_ref(m_L, LUA_REGISTRYINDEX);
        }
        reference(reference&& ref) noexcept {
            m_L = ref.m_L;
            m_index = ref.m_index;
            ref.m_index = LUA_NOREF;
        }
        ~reference() {
            if (m_index != LUA_REFNIL && m_index != LUA_NOREF) {
                luaL_unref(m_L, LUA_REGISTRYINDEX, m_index);
            }
        }
        int push_stack() const {
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            return 1;
        }

        template <typename sequence_type, typename T>
        sequence_type to_sequence() {
            lua_guard g(m_L);
            sequence_type ret;
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            if (lua_istable(m_L, -1)) {
                lua_pushnil(m_L);
                while (lua_next(m_L, -2) != 0) {
                    ret.push_back(lua_to_native<T>(m_L, -1));
                    lua_pop(m_L, 1);
                }
            }
            return ret;
        }

        template <typename associate_type, typename K, typename V>
        associate_type to_associate() {
            lua_guard g(m_L);
            associate_type ret;
            lua_rawgeti(m_L, LUA_REGISTRYINDEX, m_index);
            if (lua_istable(m_L, -1)) {
                lua_pushnil(m_L);
                while (lua_next(m_L, -2) != 0) {
                    ret.insert(std::make_pair(lua_to_native<K>(m_L, -2), lua_to_native<V>(m_L, -1)));
                    lua_pop(m_L, 1);
                }
            }
            return ret;
        }

    protected:
        lua_State*  m_L = nullptr;
        uint32_t    m_index = LUA_NOREF;
    };

    using variadic_results = std::vector<reference>;

    template <> 
    inline int native_to_lua(lua_State* L, variadic_results vr) {
        for (auto r : vr) {
            r.push_stack();
        }
        return (int)vr.size();
    }

    template <> 
    inline int native_to_lua(lua_State* L, reference r) {
        return r.push_stack();
    }

    template <> 
    inline reference lua_to_native(lua_State* L, int i) {
        lua_guard g(L);
        lua_pushvalue(L, i);
        return reference(L);
    }
}
