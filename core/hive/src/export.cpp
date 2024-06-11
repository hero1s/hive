
extern "C" {
#include "lua.h"
#include "lauxlib.h"
}

#define REGISTER_CUSTOM_LIBRARY(name, lua_c_fn)\
            int lua_c_fn(lua_State*);\
            luaL_requiref(L, name, lua_c_fn, 0);\
            lua_pop(L, 1);  /* remove lib */\

extern "C"
{
	void open_custom_libs(lua_State* L)
	{
	    lua_checkstack(L, 1000);
		//core
		REGISTER_CUSTOM_LIBRARY("lualog", luaopen_lualog);
		REGISTER_CUSTOM_LIBRARY("luapb", luaopen_luapb);
		REGISTER_CUSTOM_LIBRARY("bson", luaopen_lbson);//self
		//REGISTER_CUSTOM_LIBRARY("bson",  luaopen_bson); //cloud
		REGISTER_CUSTOM_LIBRARY("mongo", luaopen_mongo);
		REGISTER_CUSTOM_LIBRARY("ltimer", luaopen_ltimer);
		REGISTER_CUSTOM_LIBRARY("lcodec", luaopen_lcodec);
		REGISTER_CUSTOM_LIBRARY("lstdfs", luaopen_lstdfs);
		REGISTER_CUSTOM_LIBRARY("lcrypt", luaopen_lcrypt);
		REGISTER_CUSTOM_LIBRARY("luabus", luaopen_luabus);
		REGISTER_CUSTOM_LIBRARY("laes", luaopen_laes);

		//custom
		REGISTER_CUSTOM_LIBRARY("lhelper", luaopen_lhelper);
		REGISTER_CUSTOM_LIBRARY("lzset", luaopen_lzset);
		REGISTER_CUSTOM_LIBRARY("laoi", luaopen_laoi);
		REGISTER_CUSTOM_LIBRARY("lrandom", luaopen_lrandom);

		//optional

	}
}
