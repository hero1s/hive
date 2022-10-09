#pragma once
#include <memory.h>
#include "shm.h"
#include "bufpool.h"

namespace lcodec {
    //shmpool
    template<int BLOCK_SIZE = 512, int BLOCK_NUM = 2048>
    class shmpool : public buf_pool {
    public:
        ~shmpool() { clear(); }

        static shmpool* instance() {
            static shmpool<BLOCK_SIZE, BLOCK_NUM> pool;
            return &pool;
        }

        void clear() {
            detach_shm(m_shm_data, m_shm_header->shm_handle);
            delete_shm(m_shm_header->shm_handle);
        }

        bool setup(size_t shm_id) {
            size_t handle = 0;
            uint8_t* shm_data = attach_shm(shm_id, sizeof(shm_header), &handle);
            if (!shm_data) {
                return false;
            }
            m_shm_data = shm_data;
            m_shm_header = (shm_header*)shm_data;
            if (m_shm_header->shm_handle)
            {
                return true;
            }
            m_shm_header->shm_handle = handle;
            for (size_t i = 0; i < BLOCK_NUM; ++i) {
                m_shm_header->blocks[i].index = i + 1;
                m_shm_header->blocks[i].next_free = (i < (BLOCK_NUM - 1)) ? i + 2 : 0;
            }
            m_shm_header->first_free = 1;
            return true;
        }

        uint8_t* alloc() {
            std::unique_lock<std::mutex> lock(m_mutex);
            if (m_shm_header->first_free == 0) {
                return nullptr;
            }
            uint32_t index = m_shm_header->first_free - 1;
            shm_block& block = m_shm_header->blocks[index];
            m_shm_header->first_free = block.next_free;
            return block.data;
        }

        void alloc(uint8_t* data) {
            std::unique_lock<std::mutex> lock(m_mutex);
            shm_block* block = (shm_block*)(data);
            block->next_free = m_shm_header->first_free;
            m_shm_header->first_free = block->index;
        }

    protected:
        struct shm_block {
            uint8_t data[BLOCK_SIZE];
            uint16_t next_free;
            uint16_t index;
        };

        struct shm_header {
            size_t shm_handle;
            uint32_t first_free;
            shm_block blocks[BLOCK_NUM];
        };

        shmpool() {}

        std::mutex m_mutex;
        uint8_t* m_shm_data = nullptr;
        shm_header* m_shm_header = nullptr;
    };
}