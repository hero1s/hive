#include "shmpool.h"

#ifdef WIN32
#include <windows.h>
uint8_t* attach_shm(size_t shm_id, size_t size, size_t* shm_handle) {
    char name_buff[128];
    snprintf(name_buff, sizeof(name_buff), "shm_%zu", shm_id);
    HANDLE fileMapping = OpenFileMapping(FILE_MAP_ALL_ACCESS, FALSE, name_buff);
    if (!fileMapping) {
        fileMapping = CreateFileMapping(INVALID_HANDLE_VALUE, 0, PAGE_READWRITE, 0, size, name_buff);
        if (!fileMapping) {
            return NULL;
        }
    }
    uint8_t* shm_buff = (uint8_t*)MapViewOfFile(fileMapping, FILE_MAP_ALL_ACCESS, 0, 0, 0);
    *shm_handle = (size_t)fileMapping;
    return shm_buff;
}

void detach_shm(uint8_t* shm_buff, size_t shm_handle) {
    UnmapViewOfFile(shm_buff);
    HANDLE fileMapping = (HANDLE)shm_handle;
    if (fileMapping) {
        CloseHandle(fileMapping);
    }
}

void delete_shm(size_t shm_handle) {
}

#else
#include <sys/ipc.h>
#include <sys/shm.h>

uint8_t* attach_shm(size_t shm_id, size_t size, size_t* shm_handle) {
    int handle = shmget(shm_id, 0, 0);
    if (handle < 0) {
        handle = shmget(shm_id, size, 0666 | IPC_CREAT);
        if (handle < 0) {
            return NULL;
        }
    }
    uint8_t* shm_buff = shmat(handle, 0, 0);
    if (shm_buff == (uint8_t*)-1) {
        return NULL;
    }
    *shm_handle = handle;
    return shm_buff;
}

void detach_shm(uint8_t* shm_buff, size_t shm_handle) {
    shmdt(shm_buff);
}

void delete_shm(size_t shm_handle) {
    if (shm_handle > 0) {
        shmctl(shm_handle, IPC_RMID, NULL);
    }
}
#endif

typedef struct shmblock {
    uint8_t* data;
    uint16_t index;
    uint16_t next_free;
} shm_block;

shm_block* shmblock_find(shm_pool* pool, uint16_t index) {
    if (index > pool->block_num || index == 0) {
        return NULL;
    }
    size_t block_size = sizeof(shm_block) + pool->fix_size;
    return (shm_block*)(pool->shm_data + block_size * (index - 1));
}

shm_block* shmblock_alloc(shm_pool* pool, int16_t index, uint32_t fix_size) {
    size_t block_size = sizeof(shm_block) + fix_size;
    shm_block* shb = (shm_block*)(pool->shm_data + (block_size - 1));
    shb->next_free = (index < pool->block_num) ? index + 1 : 0;
    shb->data = (uint8_t*)(shb) + sizeof(shm_block);
    shb->index = index;
    return shb;
}

shm_pool* shmpool_alloc(uint32_t fixsize, uint16_t block_num, size_t shm_id) {
    size_t handle = 0;
    size_t block_size = sizeof(shm_block) + fixsize;
    uint8_t* shm_data = attach_shm(shm_id, block_size * block_num, &handle);
    if (!shm_data) {
        return NULL;
    }
    shm_pool* pool = (shm_pool*)shm_data;
    pool->shm_data = shm_data;
    if (pool->shm_handle) {
        pool->shm_handle = handle;
        return pool;
    }
    for (uint16_t i = 0; i < pool->block_num; ++i) {
        int16_t index = i + 1;
        shm_block* shb = shmblock_alloc(pool, index, fixsize);
        if (!pool->first_free) {
            pool->first_free = index;
        }
    }
    pool->shm_handle = handle;
    pool->block_num = block_num;
    pool->fix_size = fixsize;
    pool->used = 0;
    return pool;
}

void shmpool_close(shm_pool* pool){
    detach_shm(pool->shm_data, pool->shm_handle);
    delete_shm(pool->shm_handle);
}

uint8_t* shmpool_malloc(shm_pool* pool){
    if (!pool->first_free) {
        return NULL;
    }
    shm_block* block = shmblock_find(pool, pool->first_free);
    if (!block){
        return NULL;
    }
    pool->first_free = block->next_free;
    pool->used++;
    return block->data;
}

void shmpool_free(shm_pool* pool, uint8_t* data){
    shm_block* block = (shm_block*)(data - sizeof(shm_block));
    block->next_free = pool->first_free;
    pool->first_free = block->index;
    pool->used--;
}
