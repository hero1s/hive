#pragma once
#include "bufpool.h"
#include "shmpool.h"

namespace lbuffer {
    struct fixbuffer {
        uint32_t len = 0;
        uint32_t end = 0;
        uint32_t begin = 0;
        uint8_t* data = nullptr;
    };

    template<int BLOCK_SIZE = 512>
    class bufqueue {
    public:
        void init_pool() {
            m_pool = mem_pool<BLOCK_SIZE>::instance();
        }

        void init_shmpool(size_t shm_id) {
            auto pool = shmpool<BLOCK_SIZE>::instance();
            pool->setup(shm_id);
            m_pool = pool;
        }

        uint32_t size() {
            return m_size;
        }

        bool full() const {
            if (m_buffers.empty()) {
                return true;
            }
            fixbuffer& buf = m_buffers.back();
            return buf.end == buf.len;
        }

        void clear() {
            for (auto buf : m_buffers) {
                free_buf(buf);
            }
            m_buffers.clear();
            m_size = 0;
        }

        uint32_t push(const uint8_t* data, uint32_t sz) {
            uint32_t push_len = 0;
            while (push_len < sz) {
                if (full()) {
                    if (!alloc_buf()) {
                        return push_len;
                    }
                }
                fixbuffer& tail = m_buffers.back();
                long cpylen = (sz - push_len) < (tail.len - tail.end) ? (sz - push_len) : (tail.len - tail.end);
                memcpy(tail.data + tail.end, data + push_len, cpylen);
                tail.end += cpylen;
                push_len += cpylen;
            }
            m_size += sz;
            return sz;
        }

        uint32_t pop(uint8_t* data, uint32_t sz) {
            if (sz > 0 && sz <= m_size) {
                uint32_t pop_len = 0;
                while (pop_len < sz) {
                    fixbuffer& head = m_buffers.front();
                    uint32_t cpylen = (sz - pop_len) < (head.end - head.begin) ? (sz - pop_len) : (head.end - head.begin);
                    if (data) {
                        memcpy(data + pop_len, head.data + head.begin, cpylen);
                    }
                    head.begin += cpylen;
                    if (head.begin == head.end) {
                        free_buf(head);
                        m_buffers.pop_front();
                    }
                    pop_len += cpylen;
                }
                m_size -= sz;
                return sz;
            }
            return 0;
        }

        const uint8_t* front(uint32_t* len) {
            if (m_buffers.empty()) {
                return nullptr;
            }
            fixbuffer& head = m_buffers.front();
            *len = head.end - head.begin;
            return head.data + head.begin;
        }

    protected:
        bool alloc_buf() {
            uint8_t* data = nullptr;
            if (m_pool) {
                data = m_pool->alloc();
            }
            else {
                data = new uint8_t[BLOCK_SIZE];
            }
            if (!data) {
                return false;
            }
            fixbuffer fb;
            fb.data = data;
            m_buffers.push_back(fb);
            return true;
        }

        void free_buf(fixbuffer& buf) {
            if (m_pool) {
                m_pool->erase(buf.data);
            }
            else {
                delete[] buf.data;
            }
        }

    protected:
        uint32_t m_size;
        buf_pool* m_pool;
        std::list<fixbuffer> m_buffers;
    };
}
