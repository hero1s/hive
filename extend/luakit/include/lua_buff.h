#pragma once
#include "lua_slice.h"

namespace luakit {

    const size_t BUFFER_DEF = 64 * 1024;        //64K
    const size_t BUFFER_MAX = 16 * 1024 * 1024; //16M
    const size_t ALIGN_SIZE = 16;               //水位

    class luabuf {
    public:
        luabuf() { _alloc(); }
        ~luabuf() { free(m_data); }

        void reset() {
            if (m_size != BUFFER_DEF) {
                m_data = (uint8_t*)realloc(m_data, BUFFER_DEF);
            }
            m_end = m_data + BUFFER_DEF;
            m_head = m_tail = m_data;
            m_size = BUFFER_DEF;
        }

        size_t size() {
            return m_tail - m_head;
        }

        size_t capacity() {
            return m_size;
        }

        size_t empty() {
            return m_tail == m_head;
        }

        uint8_t* head() {
            return m_head;
        }

        void clean() {
            size_t data_len = m_tail - m_head;
            if (m_size > m_max && data_len < BUFFER_DEF) {
                _resize(m_size / 2);
            }
            m_head = m_tail = m_data;
        }

        size_t copy(size_t offset, const uint8_t* src, size_t src_len) {
            size_t data_len = m_tail - m_head;
            if (offset + src_len <= data_len) {
                memcpy(m_head + offset, src, src_len);
                return src_len;
            }
            return 0;
        }

        size_t push_data(const uint8_t* src, size_t push_len) {
            uint8_t* target = peek_space(push_len);
            if (target) {
                memcpy(target, src, push_len);
                m_tail += push_len;
                return push_len;
            }
            return 0;
        }

        size_t pop_data(uint8_t* dest, size_t pop_len) {
            size_t data_len = m_tail - m_head;
            if (pop_len > 0 && data_len >= pop_len) {
                memcpy(dest, m_head, pop_len);
                m_head += pop_len;
                return pop_len;
            }
            return 0;
        }

        size_t pop_size(size_t erase_len) {
            if (m_head + erase_len <= m_tail) {
                m_head += erase_len;
                size_t data_len = (size_t)(m_tail - m_head);
                if (m_size > m_max && data_len < BUFFER_DEF) {
                    _regularize();
                    _resize(m_size / 2);
                }
                return erase_len;
            }
            return 0;
        }

        uint8_t* peek_data(size_t peek_len, size_t offset = 0) {
            size_t data_len = m_tail - m_head - offset;
            if (peek_len > 0 && data_len >= peek_len) {
                return m_head + offset;
            }
            return nullptr;
        }

        size_t pop_space(size_t space_len) {
            if (m_tail + space_len <= m_end) {
                m_tail += space_len;
                return space_len;
            }
            return 0;
        }

        slice* get_slice(size_t len = 0, uint16_t offset = 0) {
            size_t data_len = m_tail - (m_head + offset);
            m_slice.attach(m_head + offset, len == 0 ? data_len : len);
            return &m_slice;
        }

        uint8_t* peek_space(size_t len) {
            size_t space_len = m_end - m_tail;
            if (space_len < len) {
                space_len = _regularize();
                if (space_len < len) {
                    size_t nsize = m_size * 2;
                    size_t data_len = m_tail - m_head;
                    while (nsize - data_len < len) {
                        nsize *= 2;
                    }
                    if (nsize >= BUFFER_MAX) {
                        return nullptr;
                    }
                    space_len = _resize(nsize);
                    if (space_len < len) {
                        return nullptr;
                    }
                }
            }
            return m_tail;
        }

        uint8_t* data(size_t* len) {
            *len = (size_t)(m_tail - m_head);
            return m_head;
        }

        std::string_view string() {
            size_t len = (size_t)(m_tail - m_head);
            return std::string_view((const char*)m_head, len);
        }

        size_t write(const char* src) {
            return push_data((const uint8_t*)src, strlen(src));
        }

        size_t write(const std::string& src) {
            return push_data((const uint8_t*)src.c_str(), src.size());
        }

        template<typename T>
        size_t write(T value) {
            return push_data((const uint8_t*)&value, sizeof(T));
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

    protected:
        //整理内存
        size_t _regularize() {
            size_t data_len = (size_t)(m_tail - m_head);
            if (m_head > m_data) {
                if (data_len > 0) {
                    memmove(m_data, m_head, data_len);
                }
                m_tail = m_data + data_len;
                m_head = m_data;
            }
            return m_size - data_len;
        }

        //重新设置长度
        size_t _resize(size_t size) {
            size_t data_len = (size_t)(m_tail - m_head);
            if (m_size == size || size < data_len || size > BUFFER_MAX) {
                return m_end - m_tail;
            }
            m_data = (uint8_t*)realloc(m_data, size);
            m_tail = m_data + data_len;
            m_end = m_data + size;
            m_head = m_data;
            m_size = size;
            return size - data_len;
        }

        void _alloc() {
            m_data = (uint8_t*)malloc(BUFFER_DEF);
            m_size = BUFFER_DEF;
            m_head = m_tail = m_data;
            m_end = m_data + BUFFER_DEF;
            m_max = m_size * ALIGN_SIZE;
        }

    private:
        size_t m_max;
        size_t m_size;
        uint8_t* m_head;
        uint8_t* m_tail;
        uint8_t* m_end;
        uint8_t* m_data;
        slice m_slice;
    };
}
