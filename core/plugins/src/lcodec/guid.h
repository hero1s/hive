#pragma once

#include <stdlib.h>
#include <time.h>
#include <math.h>

namespace lcodec {
    struct stGUID
    {
        uint16_t group : 10;
        uint16_t index : 10;
        uint16_t gtype : 5;
        uint16_t serial_index : 9;
        uint32_t time : 30;
    };
    union UGUID
    {
        stGUID   logic;  //逻辑
        int64_t  number; //数值
    };
    const uint32_t LETTER_LEN   = 11;
    const uint32_t LETTER_SIZE  = 62;

    //基准时钟：2022-10-01 08:00:00
    const uint32_t BASE_TIME    = 1664582400;

    const uint32_t MAX_GROUP    = ((1 << 10) - 1);    //1024 - 1
    const uint32_t MAX_INDEX    = ((1 << 10) - 1);    //1024 - 1
    const uint32_t MAX_TYPE     = ((1 << 5) - 1);     //32   - 1
    const uint32_t MAX_SNUM     = ((1 << 9) - 1);     //512  - 1
    
    //每一group独享一个id生成种子
    static thread_local time_t last_time = 0;
    static thread_local size_t serial_inedx_table[(1 << 10)] = { 0 };
    static thread_local UGUID  s_guid;

    static const char letter[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";

    static uint64_t guid_new(uint32_t group, uint32_t index,uint32_t gtype){
        if (group == 0) {
            group = rand();
        }
        if (index == 0) {
            index = rand();
        }
        if (gtype == 0) {
            gtype = rand();
        }
        group %= MAX_GROUP;
        index %= MAX_INDEX;
        gtype %= MAX_TYPE;

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
        s_guid.logic.group = group;
        s_guid.logic.index = index;
        s_guid.logic.gtype = gtype;
        s_guid.logic.serial_index = serial_index;
        s_guid.logic.time = last_time - BASE_TIME;
        return s_guid.number;
    }

    static int guid_encode(lua_State* L) {
        char tmp[LETTER_LEN];
        memset(tmp, 0, LETTER_LEN);
        uint64_t val = (lua_gettop(L) > 0) ? lua_tointeger(L, 1) : guid_new(0, 0, 0);
        for (int i = 0; i < LETTER_LEN; ++i) {
            tmp[i] = letter[val % LETTER_SIZE];
            val /= LETTER_SIZE;
            if (val == 0) break;
        }
        lua_pushstring(L, tmp);
        return 1;
    }

    static int find_index(char val) {
        if (val >= 97) return val - 61;
        if (val >= 65) return val - 55;
        return val - 48;
    }

    static uint64_t guid_decode(std::string sval){
        uint64_t val = 0;
        size_t len = sval.size();
        const char* cval = sval.c_str();
        for (int i = 0; i < len; ++i) {
            val += uint64_t(find_index(cval[i]) * pow(LETTER_SIZE, i));
        }
        return val;
    }

    size_t format_guid(lua_State* L) {
        if (lua_type(L, 1) == LUA_TSTRING) {
            char* chEnd = NULL;
            const char* sguid = lua_tostring(L, 1);
            return strtoull(sguid, &chEnd, 16);
        }
        else {
            return lua_tointeger(L, 1);
        }
    }

    static int guid_group(lua_State* L) {
        s_guid.number = format_guid(L);
        lua_pushinteger(L, s_guid.logic.group);
        return 1;
    }

    static int guid_index(lua_State* L) {
        s_guid.number = format_guid(L);
        lua_pushinteger(L, s_guid.logic.index);
        return 1;
    }

    static int guid_type(lua_State* L) {
        s_guid.number = format_guid(L);
        lua_pushinteger(L, s_guid.logic.gtype);
        return 1;
    }

    static int guid_time(lua_State* L) {
        s_guid.number = format_guid(L);
        lua_pushinteger(L, s_guid.logic.time + BASE_TIME);
        return 1;
    }

    static int guid_source(lua_State* L) {
        s_guid.number = format_guid(L);
        lua_pushinteger(L, s_guid.logic.group);
        lua_pushinteger(L, s_guid.logic.index);
        lua_pushinteger(L, s_guid.logic.gtype);
        lua_pushinteger(L, s_guid.logic.time + BASE_TIME);
        return 4;
    }
}
