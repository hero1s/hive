#include "stdafx.h"
#include "socket_udp.h"
#include "socket_tcp.h"
#include "lua_socket_mgr.h"

int create_socket_mgr(lua_State* L) {
	int max_fd = (int)lua_tonumber(L, 1);
	lua_socket_mgr* mgr = new lua_socket_mgr();
	if (!mgr->setup(L, max_fd)) {
		delete mgr;
		lua_pushnil(L);
		return 1;
	}
	lua_push_object(L, mgr);
	return 1;
}

int create_udp(lua_State* L) {
    socket_udp* udp = new socket_udp();
    if (!udp->setup()) {
        delete udp;
		lua_pushnil(L);
        return 1;
    }
	lua_push_object(L, udp);
    return 1;
}

int create_tcp(lua_State* L) {
    socket_tcp* tcp = new socket_tcp();
    if (!tcp->setup()) {
        delete tcp;
		lua_pushnil(L);
		return 1;
    }
	lua_push_object(L, tcp);
	return 1;
}

extern "C" {
	LUALIB_API int luaopen_luabus(lua_State* L) {
		lua_newtable(L);
		lua_set_table_function(L, -1, "create_socket_mgr", create_socket_mgr);
		lua_set_table_function(L, -1, "tcp", create_tcp);
		lua_set_table_function(L, -1, "udp", create_udp);
		return 1;
	}
}

