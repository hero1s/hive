
#pragma once

#ifdef _MSC_VER
#ifdef LBUFF_EXPORT
#define LBUFF_API _declspec(dllexport)
#else
#define LBUFF_API _declspec(dllimport)
#endif
#else
#define LBUFF_API extern
#endif

#ifdef __cplusplus
extern "C" {
#endif
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#ifndef LBUFF_EXPORT
#include "shmpool.h"
#include "bufpool.h"
#include "buffer.h"
#include "bufqueue.h"
#include "serialize.h"
#endif

#ifdef __cplusplus
}
#endif
