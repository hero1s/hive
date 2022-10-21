#pragma once
#include <list>
#include <mutex>

namespace lcodec {
    class buf_pool {
    public:
        virtual uint8_t* alloc() = 0;
        virtual void erase(uint8_t* data) = 0;
    };

    template<int BLOCK_SIZE = 512, int GROW_STEP = 16>
    class mem_pool : public buf_pool {
    public:
        ~mem_pool() { clear(); }

        static mem_pool* instance() {
            static mem_pool<BLOCK_SIZE, GROW_STEP> pool;
            return &pool;
        }

        void clear() {
            std::unique_lock<std::mutex> lock(m_mutex);
            for (auto block : m_blocks) {
                if (block) delete block;
            }
        }

        uint8_t* alloc() {
            std::unique_lock<std::mutex> lock(m_mutex);
            if (!m_first_free) {
                auto phead = new fix_block[GROW_STEP];
                if (!phead) {
                    return nullptr;
                }
                for (size_t i = 0; i < GROW_STEP; ++i) {
                    phead[i].next_free = (i < (GROW_STEP - 1)) ? &(phead[i + 1]) : nullptr;
                    m_blocks.push_front(&phead[i]);
                }
                m_first_free = phead;
            }
            fix_block* block = m_first_free;
            m_first_free = block->next_free;
            return block->data;
        }

        void erase(uint8_t* data) {
            std::unique_lock<std::mutex> lock(m_mutex);
            fix_block* block = (fix_block*)(data);
            block->next_free = m_first_free;
            m_first_free = block;
        }

    protected:
        struct fix_block {
            uint8_t data[BLOCK_SIZE];
            struct fix_block* next_free;
        };
        mem_pool() {}

        fix_block* m_first_free = nullptr;
        std::list<fix_block*> m_blocks;
        std::mutex m_mutex;
    };
}
