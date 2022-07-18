
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lua.h"
#include "lauxlib.h"


//i  - group，10位，(0~1023)
//g  - index，10位(0~1023)
//s  - 序号，13位(0~8912)
//ts - 时间戳，30位
//共63位，防止出现负数

#define GROUP_BITS  10
#define INDEX_BITS  10
#define SNUM_BITS   13
#define TIME_BITS   30

//基准时钟：2021-01-01 08:00:00
#define BASE_TIME   1625097600

#define MAX_GROUP   ((1 << GROUP_BITS) - 1) //1024 - 1
#define MAX_INDEX   ((1 << INDEX_BITS) - 1) //1024 - 1
#define MAX_SNUM    ((1 << SNUM_BITS) - 1)  //8912 - 1
#define MAX_TIME    ((1 << TIME_BITS) - 1)

//每一group独享一个id生成种子
static int serial_inedx_table[(1 << GROUP_BITS)] = { 0 };
static time_t last_time = 0;

size_t new_guid(size_t group, size_t index) {
	group %= MAX_GROUP;
	index %= MAX_INDEX;

	time_t now_time;
	time(&now_time);
	size_t serial_index = 0;
	if (now_time > last_time) {
		serial_inedx_table[group] = 0;
		last_time = now_time;
	}
	else {
		serial_index = ++serial_inedx_table[group];
		//种子溢出以后，时钟往前推
		if (serial_index >= MAX_SNUM) {
			serial_inedx_table[group] = 0;
			last_time = ++now_time;
			serial_index = 0;
		}
	}
	return ((last_time - BASE_TIME) << (SNUM_BITS + GROUP_BITS + INDEX_BITS)) |
		(serial_index << (GROUP_BITS + INDEX_BITS)) | (index << GROUP_BITS) | group;
}

static int lguid_new(lua_State* L) {
	size_t group = 0, index = 0;
	int top = lua_gettop(L);
	if (top > 1) {
		group = lua_tointeger(L, 1);
		index = lua_tointeger(L, 2);
	}
	else if (top > 0) {
		group = lua_tointeger(L, 1);
		index = rand();
	}
	else {
		group = rand();
		index = rand();
	}
	size_t guid = new_guid(group, index);
	lua_pushinteger(L, guid);
	return 1;
}

static int lguid_string(lua_State* L) {
	size_t group = 0, index = 0;
	int top = lua_gettop(L);
	if (top > 1) {
		group = lua_tointeger(L, 1);
		index = lua_tointeger(L, 2);
	}
	else if (top > 0) {
		group = lua_tointeger(L, 1);
		index = rand();
	}
	else {
		group = rand();
		index = rand();
	}
	char sguid[32];
	size_t guid = new_guid(group, index);
	snprintf(sguid, 32, "%zx", guid);
	lua_pushstring(L, sguid);
	return 1;
}

static int lguid_tostring(lua_State* L) {
	char sguid[32];
	size_t guid = lua_tointeger(L, 1);
	snprintf(sguid, 32, "%zx", guid);
	lua_pushstring(L, sguid);
	return 1;
}

static int lguid_number(lua_State* L) {
	char* chEnd = NULL;
	const char* guid = lua_tostring(L, 1);
	lua_pushinteger(L, strtoull(guid, &chEnd, 16));
	return 1;
}

size_t lguid_fmt_number(lua_State* L) {
	if (lua_type(L, 1) == LUA_TSTRING) {
		char* chEnd = NULL;
		const char* sguid = lua_tostring(L, 1);
		return strtoull(sguid, &chEnd, 16);
	}
	else {
		return lua_tointeger(L, 1);
	}
}

static int lguid_group(lua_State* L) {
	size_t guid = lguid_fmt_number(L);
	lua_pushinteger(L, guid & 0x3ff);
	return 1;
}

static int lguid_index(lua_State* L) {
	size_t guid = lguid_fmt_number(L);
	lua_pushinteger(L, (guid >> GROUP_BITS) & 0x3ff);
	return 1;
}

static int lguid_time(lua_State* L) {
	size_t guid = lguid_fmt_number(L);
	size_t time = (guid >> (GROUP_BITS + INDEX_BITS + SNUM_BITS)) & 0x3fffffff;
	lua_pushinteger(L, time + BASE_TIME);
	return 1;
}

static int lguid_source(lua_State* L) {
	size_t guid = lguid_fmt_number(L);
	lua_pushinteger(L, guid & 0x3ff);
	lua_pushinteger(L, (guid >> GROUP_BITS) & 0x3ff);
	lua_pushinteger(L, ((guid >> (GROUP_BITS + INDEX_BITS + SNUM_BITS)) & 0x3fffffff) + BASE_TIME);
	return 3;
}

static const luaL_Reg lguid_funcs[] = {
	{ "guid_new", lguid_new },
	{ "guid_string", lguid_string },
	{ "guid_tostring", lguid_tostring },
	{ "guid_number", lguid_number },
	{ "guid_group", lguid_group },
	{ "guid_index", lguid_index },
	{ "guid_time", lguid_time },
	{ "guid_source", lguid_source },
	{ NULL, NULL },
};

LUAMOD_API int luaopen_lguid(lua_State* L) {
	luaL_checkversion(L);
	luaL_newlib(L, lguid_funcs);
	return 1;
}
