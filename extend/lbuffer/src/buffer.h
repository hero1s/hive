#ifndef __BUFFER_H__
#define __BUFFER_H__

#include "lbuffer.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct varbuffer {
    uint8_t* head;
    uint8_t* tail;
    uint8_t* end;
    uint8_t* data;
    size_t ori_size;
    size_t size;
} var_buffer;

//分配buffer
LBUFF_API var_buffer* buffer_alloc(size_t size);
//释放buffer
LBUFF_API void buffer_close(var_buffer* buf);
//重置
LBUFF_API void buffer_reset(var_buffer* buf);
//获取buffsize
LBUFF_API size_t buffer_size(var_buffer* buf);
//复制
LBUFF_API size_t buffer_copy(var_buffer* buf, size_t offset, const uint8_t* src, size_t src_len);
//写入
LBUFF_API size_t buffer_apend(var_buffer* buf, const uint8_t* src, size_t src_len);
//移动头指针
LBUFF_API size_t buffer_erase(var_buffer* buf, size_t erase_len);
//全部数据
LBUFF_API uint8_t* buffer_data(var_buffer* buf, size_t* len);
//尝试读出
LBUFF_API uint8_t* buffer_peek(var_buffer* buf, size_t peek_len);
//读出
LBUFF_API size_t buffer_read(var_buffer* buf, uint8_t* dest, size_t read_len);
//返回可写指针
LBUFF_API uint8_t* buffer_attach(var_buffer* buf, size_t len);
//移动尾指针
LBUFF_API size_t buffer_grow(var_buffer* buf, size_t graw_len);

#ifdef __cplusplus
}
#endif

#endif
