
#pragma once

#include <stdint.h>
#include <thread>

//@brief  条件检测
#define CHECK_RET(EXPR, RET) \
    do {                     \
        if (!(EXPR)) {       \
            return (RET);    \
        }                    \
    } while (0);

//@brief  条件检测
#define CHECK_VOID(EXPR) \
    do {                 \
        if (!(EXPR)) {   \
            return;      \
        }                \
    } while (0);

//@brief	结构体构造函数
#define STRUCT_ZERO(TYPE) \
    TYPE() { memset(this, 0, sizeof(*this)); }

#define ZeroMemory(Destination, Length) memset((Destination), 0, (Length))

#ifndef SAFE_DELETE
#define SAFE_DELETE(x)  \
    if (nullptr != x) { \
        delete x;       \
        x = nullptr;    \
    }
#define SAFE_DELETE_ARRAY(x) \
    if (nullptr != x) {      \
        delete[] x;          \
        x = nullptr;         \
    }
#endif

#ifndef BREAK_IF
#define BREAK_IF(x) \
    if (x)          \
        break;
#endif
