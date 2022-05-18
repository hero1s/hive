#include "bufpool.h"

fix_block* fixblock_alloc(uint32_t size) {
    fix_block* fb = (fix_block*)malloc(sizeof(fix_block) + size);
    fb->data = (uint8_t*)(fb) + sizeof(fix_block);
    fb->next_free = NULL;
    fb->next = NULL;
    return fb;
}

void fixblock_close(fix_block* head) {
    while (head) {
        fix_block* next = head->next;
        free(head);
        head = next;
    }
}

buffer_pool* bufpool_alloc(uint32_t fixsize, uint16_t graw_size) {
    buffer_pool* pool = (buffer_pool*)malloc(sizeof(buffer_pool));
    pool->head = pool->tail = pool->first_free = NULL;
    pool->graw_size = graw_size;
    pool->fix_size = fixsize;
    pool->capacity = 0;
    pool->used = 0;
    return pool;
}

void bufpool_close(buffer_pool* pool) {
    fixblock_close(pool->head);
    pool->head = pool->tail = pool->first_free = NULL;
    pool->capacity = 0;
    pool->used = 0;
    free(pool);
}

uint8_t* bufpool_malloc(buffer_pool* pool) {
    if (!pool->first_free) {
        for (uint16_t i = 0; i < pool->graw_size; ++i) {
            fix_block* fb = fixblock_alloc(pool->fix_size);
            if (!pool->head) {
                pool->head = fb;
            }
            if (pool->tail) {
                pool->tail->next = fb;
            }
            if (pool->first_free) {
                fb->next_free = pool->first_free;
                pool->first_free = fb;
            }
            else {
                pool->first_free = fb;
            }
            pool->tail = fb;
            pool->capacity++;
        }
    }
    fix_block* block = pool->first_free;
    pool->first_free = block->next_free;
    pool->used++;
    return block->data;
}

void bufpool_free(buffer_pool* pool, uint8_t* data){
    fix_block* block = (fix_block*)(data - sizeof(fix_block));
    block->next_free = pool->first_free;
    pool->first_free = block;
    pool->used--;
}
