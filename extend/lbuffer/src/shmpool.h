#ifndef __SHM_POOL_H_
#define __SHM_POOL_H_

#include "lbuffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct shmpool {
    uint32_t used;
    uint32_t fix_size;
    uint8_t* shm_data;
    size_t shm_handle;
    uint16_t block_num;
    uint16_t first_free;
} shm_pool;

//shm
LBUFF_API uint8_t* attach_shm(size_t shm_id, size_t size, size_t* shm_handle);

LBUFF_API void detach_shm(uint8_t* shm_buff, size_t shm_handle);

LBUFF_API void delete_shm(size_t shm_handle);

//shmpool
//固定大小的共享内存池
LBUFF_API shm_pool* shmpool_alloc(uint32_t fixsize, uint16_t block_num, size_t shm_id);

LBUFF_API void shmpool_close(shm_pool* pool);

LBUFF_API uint8_t* shmpool_malloc(shm_pool* pool);

LBUFF_API void shmpool_free(shm_pool* pool, uint8_t* data);


#ifdef __cplusplus
}
#endif

#endif