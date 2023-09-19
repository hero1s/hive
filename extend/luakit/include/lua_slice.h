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

        slice clone() {
            return slice(m_head, m_tail - m_head);
        }

        void attach(uint8_t* data, size_t size) {
            m_head = data;
            m_tail = data + size;
        }

        uint8_t* peek(size_t peek_len, size_t offset = 0) {
            size_t data_len = m_tail - m_head - offset;
            if (peek_len > 0 && data_len >= peek_len) {
                return m_head + offset;
            }
            return nullptr;
        }

        uint8_t* erase(size_t erase_len) {
            uint8_t* data = m_head;
            if (m_head + erase_len <= m_tail) {
                m_head += erase_len;
                return data;
            }
            return nullptr;
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

        template<typename T = uint8_t>
        T* read() {
            size_t tpe_len = sizeof(T);
            size_t data_len = m_tail - m_head;
            if (tpe_len > 0 && data_len >= tpe_len) {
                uint8_t* head = m_head;
                m_head += tpe_len;
                return (T*)head;
            }
            return nullptr;
        }

        uint8_t* data(size_t* len) {
            *len = (size_t)(m_tail - m_head);
            return m_head;
        }

        uint8_t* head() {
            return m_head;
        }

        std::string_view contents() {
            size_t len = (size_t)(m_tail - m_head);
            return std::string_view((const char*)m_head, len);
        }

        std::string_view eof() {
            uint8_t* head = m_head;
            m_head = m_tail;
            size_t len = (size_t)(m_tail - head);
            return std::string_view((const char*)head, len);
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

        int recv(lua_State* L) {
            size_t data_len = m_tail - m_head;
            size_t read_len = lua_tointeger(L, 1);
            if (read_len > 0 && data_len >= read_len) {
                lua_pushlstring(L, (const char*)m_head, read_len);
                m_head += read_len;
                return 1;
            }
            return 0;
        }

        int string(lua_State* L) {
            size_t len = (size_t)(m_tail - m_head);
            lua_pushlstring(L, (const char*)m_head, len);
            return 1;
        }
        
    protected:
        uint8_t* m_head = nullptr;
        uint8_t* m_tail = nullptr;
    };
}
