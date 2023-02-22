#pragma once
#include "lua_base.h"

namespace luakit {

    class slice {
    public:
        slice() {}
        slice(uint8_t* data, size_t size) {
            attach(data, size);
        }

        void __gc() {}

        size_t size() {
            return m_tail - m_head;
        }

        size_t empty() {
            return m_tail == m_head;
        }

        void attach(uint8_t* data, size_t size) {
            m_head = data;
            m_tail = data + size;
        }

        uint8_t* peek(size_t peek_len) {
            size_t data_len = m_tail - m_head;
            if (peek_len > 0 && data_len >= peek_len) {
                return m_head;
            }
            return nullptr;
        }

        size_t erase(size_t erase_len) {
            if (m_head + erase_len <= m_tail) {
                m_head += erase_len;
                return erase_len;
            }
            return 0;
        }

        int check(lua_State* L) {
            size_t peek_len = lua_tointeger(L, 1);
            size_t data_len = m_tail - m_head;
            if (peek_len > 0 && data_len >= peek_len) {
                lua_pushlstring(L, (const char*)m_head, peek_len);
                return 1;
            }
            return 0;
        }

        size_t pop(uint8_t* dest, size_t read_len) {
            size_t data_len = m_tail - m_head;
            if (read_len > 0 && data_len >= read_len) {
                memcpy(dest, m_head, read_len);
                m_head += read_len;
                return read_len;
            }
            return 0;
        }

        int read(lua_State* L) {
            size_t data_len = m_tail - m_head;
            size_t read_len = lua_tointeger(L, 1);
            if (read_len > 0 && data_len >= read_len) {
                lua_pushlstring(L, (const char*)m_head, read_len);
                m_head += read_len;
                return 1;
            }
            return 0;
        }

        uint8_t* data(size_t* len) {
            *len = (size_t)(m_tail - m_head);
            return m_head;
        }

        uint8_t* head() {
            return m_head;
        }

        int contents(lua_State* L) {
            size_t len = (size_t)(m_tail - m_head);
            lua_pushlightuserdata(L, (void*)m_head);
            lua_pushinteger(L, len);
            return 2;
        }

        int string(lua_State* L) {
            size_t len = (size_t)(m_tail - m_head);
            lua_pushlstring(L, (const char*)m_head, len);
            return 1;
        }

    protected:
        uint8_t* m_head;
        uint8_t* m_tail;
    };
}
