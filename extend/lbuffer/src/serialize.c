#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#include "buffer.h"
#include "serialize.h"

#define TYPE_NIL            0
#define TYPE_BOOLEAN        1
#define TYPE_INTEGER        2
#define TYPE_NUMBER         3
#define TYPE_TABLE          4
#define TYPE_STRING         5

#define TYPE_STRING_IDX1    0
#define TYPE_STRING_BYTE    1
#define TYPE_STRING_SHORT   2
#define TYPE_STRING_IDX2    3
#define TYPE_STRING_LONG    4

#define TYPE_TABLE_HEAD     1
#define TYPE_TABLE_TAIL     2

#define TYPE_INTEGER_ZERO   0
#define TYPE_INTEGER_UI8    1
#define TYPE_INTEGER_UI16   2
#define TYPE_INTEGER_UI32   3
#define TYPE_INTEGER_I8     4
#define TYPE_INTEGER_I16    5
#define TYPE_INTEGER_I32    6
#define TYPE_INTEGER_I64    7

#define MAX_DEPTH           16
#define COMBINE_TYPE(t,s)   ((t) | (s) << 3)

typedef struct share_string {
    uint8_t* buf;
    uint32_t len;
    uint16_t index;
    struct share_string* next;
} shstring;

static shstring* string_alloc(uint16_t index) {
    shstring* s = (shstring*)malloc(sizeof(shstring));
    s->index = index;
    s->next = NULL;
    s->buf = NULL;
    s->len = 0;
    return s;
}

static void string_push(shstring** tail, uint8_t* buf, int sz) {
    (*tail)->len = sz;
    (*tail)->buf = malloc(sz);
    memcpy((*tail)->buf, buf, sz);
    uint16_t index = (*tail)->index;
    (*tail) = (*tail)->next = string_alloc(index + 1);
}

static uint16_t index_find(shstring* head, uint8_t* str, int sz) {
    shstring* ptr = head;
    while (ptr && ptr->buf) {
        if (strncmp(ptr->buf, str, sz) == 0){
            return ptr->index;
        }
        ptr = ptr->next;
    }
    string_push(&ptr, str, sz);
    return 0;
}

static uint8_t* string_find(shstring* head, uint16_t index, int* sz) {
    shstring* ptr = head;
    while (ptr) {
        if (ptr->index == index) {
            *sz = ptr->len;
            return ptr->buf;
        }
        ptr = ptr->next;
    }
    return NULL;
}

static void string_close(shstring* head) {
    while (head) {
        shstring* next = head->next;
        if (head->buf) {
            free(head->buf);
            head->buf = NULL;
        }
        free(head);
        head = next;
    }
}

#define STRING_READ(buf, tail, type, sz, sz_len) {\
    type size = 0;\
    if (buffer_read(buf, (uint8_t*)&size, sz_len)) {\
        uint8_t* dest = (uint8_t*)malloc(size);\
        if (buffer_read(buf, dest, size)) {\
            string_push(tail, dest, size);\
            *sz = size;\
            return dest;\
        }\
    }\
    return NULL;\
}

#define INX_STRING_READ(buf, head, type, sz) {\
    type index = 0;\
    if (buffer_read(buf, (uint8_t*)&index, sizeof(index))) {\
        return string_find(head, index, sz);\
    }\
    return NULL;\
}

static uint8_t* string_read(var_buffer* buf, shstring* head, shstring** tail, uint8_t type, uint32_t* sz) {
    switch (type) {
    case TYPE_STRING_BYTE:
        STRING_READ(buf, tail, uint8_t, sz, type);
    case TYPE_STRING_SHORT:
        STRING_READ(buf, tail, uint16_t, sz, type);
    case TYPE_STRING_LONG:
        STRING_READ(buf, tail, uint32_t, sz, type);
    case TYPE_STRING_IDX1:
        INX_STRING_READ(buf, head, uint8_t, sz);
    case TYPE_STRING_IDX2:
        INX_STRING_READ(buf, head, uint16_t, sz);
    }
    return NULL;
}

#define ENCODE_TYPE(L, buf, type) {\
    uint8_t t = type;\
    if (0 == buffer_apend(buf, &(t), 1)){ \
        luaL_error(L, "encode can't pack type"); \
    }\
}

#define ENCODE_VALUE(L, buf, type, val, val_type) {\
    val_type vtype = val;\
    ENCODE_TYPE(L, buf, type)\
    if (0 == buffer_apend(buf, (uint8_t*)&vtype, sizeof(vtype))){\
        luaL_error(L, "encode can't pack value"); \
    }\
}

#define ENCODE_COMBINE_STRING(L, buf, val, sz, type, val_type) {\
    ENCODE_VALUE(L, buf, type, sz, val_type)\
    if (0 == buffer_apend(buf, val, sz)){\
        luaL_error(L, "encode can't pack string"); \
    }\
}

#define ENCODE_STRING(L, head, buf, index) {\
    size_t sz = 0;\
    uint8_t* str = (uint8_t*)lua_tolstring(L, index, &sz);\
    uint16_t sindex = index_find(head, str, sz);\
    if (sindex > 0xff) \
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_STRING, TYPE_STRING_IDX2), sindex, uint16_t)\
    else if (sindex > 0) \
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_STRING, TYPE_STRING_IDX1), sindex, uint8_t)\
    else if (sz <= 0xff)\
    ENCODE_COMBINE_STRING(L, buf, str, sz, COMBINE_TYPE(TYPE_STRING, TYPE_STRING_BYTE), uint8_t)\
    else if (sz <= 0xffff)\
    ENCODE_COMBINE_STRING(L, buf, str, sz, COMBINE_TYPE(TYPE_STRING, TYPE_STRING_SHORT), uint16_t)\
    else\
    ENCODE_COMBINE_STRING(L, buf, str, sz, COMBINE_TYPE(TYPE_STRING, TYPE_STRING_LONG), uint32_t)\
}

#define ENCODE_INTEGER(L, buf, index) {\
    lua_Integer val = lua_tointeger(L, index);\
    if (val == 0)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_ZERO), val, uint8_t)\
    else if (val != (int32_t)val)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_I64), val, int64_t)\
    else if (val > 0xffff)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_UI32), val, uint32_t)\
    else if (val > 0xff)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_UI16), val, uint16_t)\
    else if (val > 0)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_UI8), val, uint8_t)\
    else if (val < -0x8000)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_I32), val, int32_t)\
    else if (val < -0x80)\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_I16), val, int16_t)\
    else\
    ENCODE_VALUE(L, buf, COMBINE_TYPE(TYPE_INTEGER, TYPE_INTEGER_I8), val, int8_t)\
}

static void encode_number(lua_State* L, var_buffer* buf, int index) {
    if (lua_isinteger(L, index)) {
        ENCODE_INTEGER(L, buf, index)
        return;
    }
    ENCODE_VALUE(L, buf, TYPE_NUMBER, lua_tonumber(L, index), lua_Number);
}

static void encode_one(lua_State* L, shstring* head, var_buffer* buf, int index, int depth);
static void encode_table(lua_State* L, shstring* head, var_buffer* buf, int index, int depth) {
    if (index < 0) {
        index = lua_gettop(L) + index + 1;
    }
    ENCODE_TYPE(L, buf, COMBINE_TYPE(TYPE_TABLE, TYPE_TABLE_HEAD));
    lua_pushnil(L);
    while (lua_next(L, index) != 0) {
        encode_one(L, head, buf, -2, depth);
        encode_one(L, head, buf, -1, depth);
        lua_pop(L, 1);
    }
    ENCODE_TYPE(L, buf, COMBINE_TYPE(TYPE_TABLE, TYPE_TABLE_TAIL));
}

static void encode_one(lua_State* L, shstring* head, var_buffer* buf, int index, int depth) {
    if (depth > MAX_DEPTH) {
        luaL_error(L, "encode can't pack too depth table");
    }
    int type = lua_type(L, index);
    switch (type) {
    case LUA_TNIL:
        ENCODE_TYPE(L, buf, TYPE_NIL);
        break;
    case LUA_TBOOLEAN:
        ENCODE_TYPE(L, buf, COMBINE_TYPE(TYPE_BOOLEAN, lua_toboolean(L, index) ? 1 : 0));
        break;
    case LUA_TSTRING:
        ENCODE_STRING(L, head, buf, index);
        break;
    case LUA_TNUMBER: 
        encode_number(L, buf, index);
        break;
    case LUA_TTABLE: 
        encode_table(L, head, buf, index, depth + 1);
        break;
    default:
        break;
    }
}

#define READ_VALUE(L, buf, type) \
type value = 0; \
if (buffer_read(buf, (uint8_t*)&value, sizeof(value)) == 0) {\
    luaL_error(L, "decode can't read value"); \
}

#define DECODE_VALUE(L, buf, type, loadL) {\
    READ_VALUE(L, buf, type)\
    loadL(L, value); \
}\
break;

static void decode_integer(lua_State* L, var_buffer* buf, int sub_type) {
    switch (sub_type) {
    case TYPE_INTEGER_ZERO:
        lua_pushinteger(L, 0);
        break;
    case TYPE_INTEGER_I8:
        DECODE_VALUE(L, buf, int8_t, lua_pushinteger)
    case TYPE_INTEGER_UI8: 
        DECODE_VALUE(L, buf, uint8_t, lua_pushinteger)
    case TYPE_INTEGER_I16: 
        DECODE_VALUE(L, buf, int16_t, lua_pushinteger)
    case TYPE_INTEGER_UI16: 
        DECODE_VALUE(L, buf, uint16_t, lua_pushinteger)
    case TYPE_INTEGER_I32: 
        DECODE_VALUE(L, buf, int32_t, lua_pushinteger)
    case TYPE_INTEGER_UI32: 
        DECODE_VALUE(L, buf, uint32_t, lua_pushinteger)
    case TYPE_INTEGER_I64: 
        DECODE_VALUE(L, buf, int64_t, lua_pushinteger)
    default:
        luaL_error(L, "decode can't read integer");
    }
}

static void decode_string(lua_State* L, shstring* head, shstring** tail, var_buffer* buf, int sub_type) {
    uint32_t len = 0;
    uint8_t* str = string_read(buf, head, tail, sub_type, &len);
    if (!str) {
        luaL_error(L, "decode can't read string");
    }
    lua_pushlstring(L, str, len);
}

static int decode_one(lua_State* L, shstring* head, shstring** tail, var_buffer* buf);
static void decode_table(lua_State* L, shstring* head, shstring** tail, var_buffer* buf, int sub_type) {
    if (sub_type == TYPE_TABLE_HEAD) {
        uint8_t ttail = COMBINE_TYPE(TYPE_TABLE, TYPE_TABLE_TAIL);
        lua_createtable(L, 0, 0);
        do {
            if (decode_one(L, head, tail, buf) == ttail) {
                break;
            }
            decode_one(L, head, tail, buf);
            lua_rawset(L, -3);
        } while (1);
    }
}

static void decode_value(lua_State* L, shstring* head, shstring** tail, var_buffer* buf, int type, int sub_type) {
    switch (type) {
    case TYPE_NIL:
        lua_pushnil(L);
        break;
    case TYPE_BOOLEAN:
        lua_pushboolean(L, sub_type);
        break;
    case TYPE_INTEGER:
        decode_integer(L, buf, sub_type);
        break;
    case TYPE_NUMBER:
        DECODE_VALUE(L, buf, double, lua_pushnumber);
        break;
    case TYPE_STRING:
        decode_string(L, head, tail, buf, sub_type);
        break;
    case TYPE_TABLE:
        decode_table(L, head, tail, buf, sub_type);
        break;
    default:
        luaL_error(L, "decode can't push value (unsupport type)");
        break;
    }
}

static int decode_one(lua_State* L, shstring* head, shstring** tail, var_buffer* buf) {
    uint8_t type = 0;
    if (buffer_read(buf, &type, sizeof(type)) == 0) {
        luaL_error(L, "unserialize can't unpack one value");
    }
    decode_value(L, head, tail, buf, type & 0x7, type >> 3);
    return type;
}

void encode(lua_State* L, var_buffer* buf, int from) {
    shstring* head = string_alloc(1);
    int n = lua_gettop(L) - from;
    for (int i = 1; i <= n; i++) {
        encode_one(L, head, buf, from + i, 0);
    }
    string_close(head);
}

void decode(lua_State* L, var_buffer* buf) {
    shstring* head = string_alloc(1);
    shstring* tail = head;
    while (1) {
        uint8_t type = 0;
        if (buffer_read(buf, (char*)&type, 1) == 0)
            break;
        decode_value(L, head, &tail, buf, type & 0x7, type >> 3);
    }
    string_close(head);
}

#define SERIALIZE_VALUE(buf, val) buffer_apend(buf, val, strlen(val))
#define SERIALIZE_QUOTE(buf, val, l, r)\
SERIALIZE_VALUE(buf, l); \
SERIALIZE_VALUE(buf, val); \
SERIALIZE_VALUE(buf, r);
#define SERIALIZE_UDATA(buf, val) SERIALIZE_QUOTE(buf, val ? val : "userdata(null)", "'", "'")
#define SERIALIZE_CRCN(buf, cnt, line) {\
    if(line > 0) {\
        buffer_apend(buf, "\n", 1);\
        for(int i = 0; i < cnt - 1; ++i) {\
            buffer_apend(buf, "\t", 1);\
        }\
    }\
}

static void serialize_table(lua_State* L, var_buffer* buf, int index, int depth, int line) {
    if (index < 0) {
        index = lua_gettop(L) + index + 1;
    }
    int size = 0;
    lua_pushnil(L);
    SERIALIZE_VALUE(buf, "{");
    SERIALIZE_CRCN(buf, depth, line);
    while (lua_next(L, index) != 0) {
        if (size++ > 0) {
            SERIALIZE_VALUE(buf, ",");
            SERIALIZE_CRCN(buf, depth, line);
        }
        if (lua_isnumber(L, -2)) {
            lua_pushnil(L);
            lua_copy(L, -3, -1);
            SERIALIZE_QUOTE(buf, lua_tostring(L, -1), "[", "]=");
            lua_pop(L, 1);
        }
        else if (lua_type(L, -2) == LUA_TSTRING) {
            SERIALIZE_VALUE(buf, lua_tostring(L, -2));
            SERIALIZE_VALUE(buf, "=");
        }
        else {
            serialize(L, buf, -2, depth, line);
        }
        serialize(L, buf, -1, depth, line);
        lua_pop(L, 1);
    }
    SERIALIZE_CRCN(buf, depth - 1, line);
    SERIALIZE_VALUE(buf, "}");
}

void serialize(lua_State* L, var_buffer* buf, int index, int depth, int line) {
    if (depth > MAX_DEPTH) {
        luaL_error(L, "serialize can't pack too depth table");
    }
    int type = lua_type(L, index);
    switch (type) {
    case LUA_TNIL:
        SERIALIZE_VALUE(buf, "nil");
        break;
    case LUA_TBOOLEAN:
        SERIALIZE_VALUE(buf, lua_toboolean(L, index) ? "true" : "false");
        break;
    case LUA_TSTRING:
        SERIALIZE_QUOTE(buf, lua_tostring(L, index), "'", "'");
        break;
    case LUA_TNUMBER:
        SERIALIZE_VALUE(buf, lua_tostring(L, index));
        break;
    case LUA_TTABLE:
        serialize_table(L, buf, index, depth + 1, line);
        break;
    case LUA_TUSERDATA:
    case LUA_TLIGHTUSERDATA:
        SERIALIZE_UDATA(buf, lua_tostring(L, index));
        break;
    default:
        SERIALIZE_QUOTE(buf, lua_typename(L, type), "'unsupport(", ")'");
        break;
    }
}
