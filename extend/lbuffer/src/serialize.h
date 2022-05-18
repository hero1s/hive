#ifndef __SERIALIZE_H__
#define __SERIALIZE_H__

#include "lbuffer.h"

#ifdef __cplusplus
extern "C" {
#endif

#include <lua.h>
#include <lauxlib.h>

LBUFF_API void encode(lua_State* L, var_buffer* buf, int from);
LBUFF_API void decode(lua_State* L, var_buffer* buf);

LBUFF_API void serialize(lua_State* L, var_buffer* buf, int index, int depth, int crcn);

#ifdef __cplusplus
}
#endif

#endif