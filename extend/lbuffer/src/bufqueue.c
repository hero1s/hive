#include "bufqueue.h"
#include <memory.h>

fix_buffer* fixbuf_alloc(buffer_queue* queue) {
    uint8_t* data = NULL;
    if (queue->buf_pool) {
        data = bufpool_malloc(queue->buf_pool);
    }
    else if (queue->sh_pool){
        data = shmpool_malloc(queue->sh_pool);
    }
    else {
        data = (uint8_t*)malloc(queue->fix_size);
    }
    if (!data){
        return NULL;
    }
    fix_buffer* fb = (fix_buffer*)malloc(sizeof(fix_buffer));
    fb->begin = fb->end = 0;
    fb->data = data;
    fb->next = NULL;
    fb->len = 0;
    return fb;
}

void fixbuf_close(buffer_queue* queue, fix_buffer* head) {
    while (head) {
        fix_buffer* next = head->next;
        if (head->data) {
            if (queue->buf_pool) {
                bufpool_free(queue->buf_pool, head->data);
            }
            else if (queue->sh_pool) {
               shmpool_free(queue->sh_pool, head->data);
            }
            else {
                free(head->data);
            }
            head->data = NULL;
        }
        free(head);
        head = next;
    }
}

buffer_queue* bufqueue_alloc(uint32_t fix_size, uint16_t graw_size) {
    buffer_queue* queue = (buffer_queue*)malloc(sizeof(buffer_queue));
    queue->buf_pool = bufpool_alloc(fix_size, graw_size);
    queue->head = queue->tail = NULL;
    queue->fix_size = fix_size;
    queue->size = 0;
    return queue;
}

buffer_queue* shmqueue_alloc(uint32_t fix_size, uint16_t block_num, size_t shm_id) {
    buffer_queue* queue = (buffer_queue*)malloc(sizeof(buffer_queue));
    queue->sh_pool = shmpool_alloc(fix_size, block_num, shm_id);
    queue->head = queue->tail = NULL;
    queue->fix_size = fix_size;
    queue->size = 0;
    return queue;
}

uint32_t bufqueue_size(buffer_queue* queue) {
    return queue->size;
}

uint32_t bufqueue_empty(buffer_queue* queue) {
    return queue->size == 0;
}

uint32_t queue_full(buffer_queue* queue) {
    return queue->tail->end == queue->tail->len;
}

void bufqueue_clear(buffer_queue* queue) {
    fixbuf_close(queue, queue->head);
    queue->head = queue->tail = NULL;
    queue->size = 0;
}

void bufqueue_close(buffer_queue* queue) {
    bufqueue_clear(queue);
    if (queue->buf_pool) {
        bufpool_close(queue->buf_pool);
    }
    if (queue->sh_pool) {
        shmpool_close(queue->sh_pool);
    }
    free(queue);
}

uint32_t bufqueue_push(buffer_queue* queue, const uint8_t* data, uint32_t sz) {
    uint32_t push_len = 0;
    while (push_len < sz) {
        if (bufqueue_empty(queue) || queue_full(queue)) {
            fix_buffer* fb = fixbuf_alloc(queue);
            if (!fb) {
                return 0;
            }
            if (!queue->head) {
                queue->head = fb;
            }
            if (queue->tail) {
                queue->tail->next = fb;
            }
            queue->tail = fb;
        }
        fix_buffer* tail = queue->tail;
        long cpylen = (sz - push_len) < (tail->len - tail->end) ? (sz - push_len) : (tail->len - tail->end);
        memcpy(tail->data + tail->end, data + push_len, cpylen);
        tail->end += cpylen;
        push_len += cpylen;
    }
    queue->size += sz;
    return sz;
}

uint32_t bufqueue_pop(buffer_queue* queue, uint8_t* data, uint32_t sz) {
    if (sz > 0 && sz <= queue->size) {
        uint32_t pop_len = 0;
        while (pop_len < sz) {
            fix_buffer* head = queue->head;
            uint32_t cpylen = (sz - pop_len) < (head->end - head->begin) ? (sz - pop_len) : (head->end - head->begin);
            if (data) {
                memcpy(data + pop_len, head->data + head->begin, cpylen);
            }
            head->begin += cpylen;
            if (head->begin == head->end) {
                queue->head = head->next;
                head->next = NULL;
                fixbuf_close(queue, head);
            }
            pop_len += cpylen;
        }
        queue->size -= sz;
        return sz;
    }
    return 0;
}

const uint8_t* bufqueue_front(buffer_queue* queue, uint32_t* len) {
    if (!queue->head) {
        return NULL;
    }
    fix_buffer* head = queue->head;
    *len = head->end - head->begin;
    return head->data + head->begin;
}

