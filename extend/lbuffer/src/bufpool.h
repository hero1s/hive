#ifndef __BUF_POOL_H_
#define __BUF_POOL_H_

#include "lbuffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct fixblock {
    uint8_t* data;
    struct fixblock* next;
    struct fixblock* next_free;
} fix_block;

typedef struct bufpool {
    uint32_t used;
    uint32_t capacity;
    uint32_t fix_size;
    uint16_t graw_size;
    fix_block* head;
    fix_block* tail;
    fix_block* first_free;
} buffer_pool;

LBUFF_API buffer_pool* bufpool_alloc(uint32_t fixsize, uint16_t graw_size);

LBUFF_API void bufpool_close(buffer_pool* pool);

LBUFF_API uint8_t* bufpool_malloc(buffer_pool* pool);

LBUFF_API void bufpool_free(buffer_pool* pool, uint8_t* data);


#ifdef __cplusplus
}
#endif

#endif