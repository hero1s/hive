#ifndef __HTTP_H__
#define __HTTP_H__

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include<stdarg.h>
#include <assert.h>
#include <memory.h>
#include <string.h>

#ifdef _MSC_VER
#ifdef LHTTP_EXPORT
#define LHTTP_API _declspec(dllexport)
#else
#define LHTTP_API _declspec(dllimport)
#endif
#else
#define LHTTP_API extern
#endif

// enums
//---------------------------------------------------------------------
// token枚举
enum hs_token {
    HS_TOK_NONE, HS_TOK_METHOD, HS_TOK_TARGET, HS_TOK_VERSION,
    HS_TOK_HEADER_KEY, HS_TOK_HEADER_VAL, HS_TOK_CHUNK_BODY, HS_TOK_BODY,
    HS_TOK_BODY_STREAM, HS_TOK_REQ_END, HS_TOK_EOF, HS_TOK_ERROR,
    HS_TOK_URL, HS_TOK_QUERY_KEY, HS_TOK_QUERY_VAL
};

// 词法分析中的状态
enum hs_state {
    ST, MT, MS, TR, TS, VN, RR, RN, HK, HS, HV, HR, HE,
    ER, HN, BD, CS, CB, CE, CR, CN, CD, C1, C2, BR, HS_STATE_LEN
};

// 字符类型
enum hs_char_type {
    /*空格    LF     CR     冒号    TAB      分号     */
    HS_SPC, HS_NL, HS_CR, HS_COLN, HS_TAB, HS_SCOLN,
    /*0-9      A-Fa-f  g-zG-Z     符号  []{}()/\<=>?@" 其他 */
    HS_DIGIT, HS_HEX, HS_ALPHA, HS_TCHAR, HS_VCHAR, HS_ETC, HS_CHAR_TYPE_LEN
};

// 元数据状态
enum hs_meta_state {
    M_WFK, M_ANY, M_MTE, M_MCL, M_CLV, M_MCK, M_SML, M_CHK, M_BIG, M_ZER, M_CSZ,
    M_CBD, M_LST, M_STR, M_SEN, M_BDY, M_END, M_ERR
};

// 元数据类型
enum hs_meta_type {
    HS_META_NOT_CONTENT_LEN, HS_META_NOT_TRANSFER_ENC, HS_META_END_KEY,
    HS_META_END_VALUE, HS_META_END_HEADERS, HS_META_LARGE_BODY,
    HS_META_TYPE_LEN
};

// constants
//-----------------------------------------------------------------
#define HTTP_CLOSE      0
#define HTTP_KEEP_ALIVE 1

// http session states
#define HTTP_REQUEST_PARSE      0
#define HTTP_SESSION_FINISH     1
#define HTTP_REQUEST_ERROR      2

// http session flags
#define HTTP_END_SESSION        0x2
#define HTTP_AUTOMATIC          0x8
#define HTTP_CHUNKED_RESPONSE   0x20

// Application configurable
#define HTTP_REQUEST_BUF_SIZE           1024
#define HTTP_RESPONSE_BUF_SIZE          1024
#define HTTP_REQUEST_TIMEOUT            20
#define HTTP_KEEP_ALIVE_TIMEOUT         120
#define HTTP_MAX_HEADER_COUNT           127
#define HTTP_MAX_TOKEN_LENGTH           8192        // 8kb
#define HTTP_MAX_REQUEST_BUF_SIZE       8388608     // 8mb
#define HTTP_MAX_TOTAL_EST_MEM_USAGE    4294967296  // 4gb

#define HS_META_NEXT            0
#define HS_META_NON_ZERO        0
#define HS_META_NOT_CHUNKED     0
#define HS_META_END_CHK_SIZE    1
#define HS_META_END_CHUNK       2

// stream flags
#define HS_SF_CONSUMED          0x1

// parser flags
#define HS_PF_IN_CONTENT_LEN    0x1
#define HS_PF_IN_TRANSFER_ENC   0x2
#define HS_PF_CHUNKED           0x4
#define HS_PF_CKEND             0x8
#define HS_PF_REQ_END           0x10

// 当请求正文被分块或正文太大而无法放入内存时，将设置此标志。这意味着必须使用http_request_read_chunk函数逐段读取正文。
#define HTTP_FLG_CHUNK          0x1

#define HTTP_FLAG_SET(var, flag)    var |= flag
#define HTTP_FLAG_CLEAR(var, flag)  var &= ~flag
#define HTTP_FLAG_CHECK(var, flag)  (var & flag)

// structs
//-----------------------------------------------------------------
// 用于读取请求详细信息的字符串类型
typedef struct http_string_s {
    char const* buf;
    int len;
} http_string_t;

typedef struct {
    int index;
    int len;
    int type;
} http_token_t;

typedef struct {
    http_token_t* buf;
    int capacity;
    int size;
} http_token_dyn_t;

typedef struct {
    char* buf;
    int64_t total_bytes;
    int32_t capacity;
    int32_t length;
    int32_t index;
    int32_t anchor;
    http_token_t token;
    uint8_t flags;
} http_stream_t;

//http_parser_t
typedef struct {
    int64_t content_length;
    int64_t body_consumed;
    int16_t match_index;
    int16_t header_count;
    int8_t state;
    int8_t meta;
} http_parser_t;

typedef struct http_header_s {
    char const* key;
    char const* value;
    struct http_header_s* next;
} http_header_t;

typedef struct http_response_s {
    int status;
    int content_length;
    char const* body;
    http_header_t* headers;
} http_response_t;

typedef struct http_request_s {
    char flags;
    int state;
    int timeout;
    http_stream_t stream;
    http_parser_t parser;
    http_token_dyn_t tokens;
} http_request_t;

//http stream
//----------------------------------------------------------------
LHTTP_API int http_stream_append(http_stream_t* stream, const char* buf, int len);

LHTTP_API int http_request_has_flag(http_request_t* request, int flag);

LHTTP_API http_string_t http_request_method(http_request_t* request);

LHTTP_API http_string_t http_request_url(http_request_t* request);

LHTTP_API http_string_t http_request_body(http_request_t* request);

LHTTP_API int http_request_headers_iterator(http_request_t* request, http_string_t* key, http_string_t* val, int* iter);

LHTTP_API int http_request_querys_iterator(http_request_t* request, http_string_t* key, http_string_t* val, int* iter);

LHTTP_API http_string_t http_request_header(http_request_t* request, char const* key);

LHTTP_API http_string_t http_request_query(http_request_t* request, char const* key);

LHTTP_API http_string_t http_request_chunk(struct http_request_s* request);

//http response 接口
//--------------------------------------------------------------------------
LHTTP_API http_response_t* http_response_init();

LHTTP_API void http_response_header(http_response_t* response, char const* key, char const* value);

LHTTP_API void http_response_status(http_response_t* response, int status);

LHTTP_API void http_response_body(http_response_t* response, char const* body, int length);

LHTTP_API void http_close_response(http_response_t* response);

LHTTP_API void http_clean_response(http_response_t* response);

LHTTP_API void http_close_request(http_request_t* request);

LHTTP_API void http_clean_request(http_request_t* request);

LHTTP_API http_string_t http_respond_chunk(http_request_t* request, http_response_t* response);

LHTTP_API http_string_t http_respond_chunk_end(http_request_t* request, http_response_t* response);

LHTTP_API http_string_t http_respond(http_request_t* request, http_response_t* response);

LHTTP_API http_string_t http_request_response(http_request_t* request, int code, char const* type, char const* message);

LHTTP_API http_request_t* http_request_init();

LHTTP_API void http_request_reset(http_request_t* request);

LHTTP_API void http_process_request(http_request_t* request);

#endif // __HTTP_H__
