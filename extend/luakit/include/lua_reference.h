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

    protected:
        lua_State*  m_L = nullptr;
        int32_t     m_index = LUA_NOREF;
    };

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
