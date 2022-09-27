
#include <stdlib.h>
#include <time.h>
#include <math.h>
#include <vector>
#include <string>
#include <iostream>

#include "lua_kit.h"

using namespace std;

namespace guid
{

	//i  - group， 10位(0~1023)
	//g  - index， 10位(0~1023)
	//s  - 序号，  13位(0~8912)
	//ts - 时间戳，30位
	//共63位，防止出现负数

	static constexpr int GROUP_BITS = 10;
	static constexpr int INDEX_BITS = 10;
	static constexpr int SNUM_BITS = 13;
	static constexpr int TIME_BITS = 30;

	//基准时钟：2021-01-01 08:00:00
	static constexpr int BASE_TIME = 1625097600;

	static constexpr int MAX_GROUP = ((1 << GROUP_BITS) - 1); //1024 - 1
	static constexpr int MAX_INDEX = ((1 << INDEX_BITS) - 1); //1024 - 1
	static constexpr int MAX_SNUM = ((1 << SNUM_BITS) - 1);  //8912 - 1
	static constexpr int MAX_TIME = ((1 << TIME_BITS) - 1);

	//每一group独享一个id生成种子
	static int serial_inedx_table[(1 << GROUP_BITS)] = { 0 };
	static time_t last_time = 0;

	//基码(去掉0,1)共60位
	static  const vector<char> BASE =
	{ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N','O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n','o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
	  '2', '3', '4', '5', '6', '7', '8', '9'
	};
	//补位码不能在base数组里,否则无法区分
	static const char PAD = '0';
	//生成邀请码(数字变字符,根据数字大小估算长度,32位整数小于6字符,64位整数10字符)
	string encode_code(uint64_t guid,size_t code_size) {
		string code;
		auto base_len = BASE.size();
		while (guid > 0)
		{
			auto mod = guid % base_len;
			guid = guid / base_len;
			code.push_back(BASE[mod]);
		}
		auto code_len = code.size();
		//小于设置长度随机补位
		if (code_len < code_size) {
			code.push_back(PAD);
			for (auto i = 0; i < code_size - code_len - 1; i++) {
				code.push_back(BASE[rand() % base_len]);
			}
		}
		return code;
	}
	//反解邀请码(字符串转数字)
	uint64_t decode_code(string code) {
		static vector<char> BASE_MAP;
		if (BASE_MAP.empty()) {
			BASE_MAP.resize(256);
			for (char i = 0; i < BASE.size(); i++) {
				BASE_MAP[BASE[i]] = i;
			}
		}
		uint64_t guid = 0;
		size_t r = 0;
		auto base_len = BASE.size();
		for (size_t i = 0; i < code.size(); i++) {
			if (code[i] == PAD) {
				break;
			}
			auto index = BASE_MAP[code[i]];
			guid += uint64_t(index * pow(base_len,r));
			r++;
		}
		return guid;
	}

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

	luakit::lua_table open_lguid(lua_State* L) {
		luakit::kit_state kit_state(L);
		auto luaguid = kit_state.new_table();
		
		luaguid.set_function("guid_new", lguid_new);
		luaguid.set_function("guid_string", lguid_string);
		luaguid.set_function("guid_tostring", lguid_tostring);
		luaguid.set_function("guid_number", lguid_number);
		luaguid.set_function("guid_group", lguid_group);
		luaguid.set_function("guid_index", lguid_index);
		luaguid.set_function("guid_time", lguid_time);
		luaguid.set_function("guid_source", lguid_source);
		luaguid.set_function("encode_code", encode_code);
		luaguid.set_function("decode_code", decode_code);

		return luaguid;
	}
}

extern "C" {
	LUAMOD_API int luaopen_lguid(lua_State* L) {
		return guid::open_lguid(L).push_stack();
	}
}


