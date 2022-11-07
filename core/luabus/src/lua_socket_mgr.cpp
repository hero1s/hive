#include "stdafx.h"
#include "var_int.h"
#include "lua_socket_mgr.h"
#include "lua_socket_node.h"

// 64M
constexpr int LUA_AR_BUFFER_SIZE = 64 * 1024 * 1024;

EXPORT_CLASS_BEGIN(lua_socket_mgr)
EXPORT_LUA_FUNCTION(wait)
EXPORT_LUA_FUNCTION(listen)
EXPORT_LUA_FUNCTION(connect)
EXPORT_LUA_FUNCTION(set_package_size)
EXPORT_LUA_FUNCTION(set_lz_threshold)
EXPORT_LUA_FUNCTION(set_master)
EXPORT_LUA_FUNCTION(map_token)
EXPORT_LUA_FUNCTION(set_rpc_key)
EXPORT_CLASS_END()

lua_socket_mgr::~lua_socket_mgr() {
}

bool lua_socket_mgr::setup(lua_State* L, int max_fd) {
	m_lvm = L;
	m_mgr = std::make_shared<socket_mgr>();
	m_archiver = std::make_shared<lua_archiver>(LUA_AR_BUFFER_SIZE);
	m_router = std::make_shared<socket_router>(m_mgr);
	return m_mgr->setup(max_fd);
}

int lua_socket_mgr::listen(lua_State* L) {
	const char* ip = lua_tostring(L, 1);
	int port = (int)lua_tointeger(L, 2);
	if (ip == nullptr || port <= 0) {
		lua_pushnil(L);
		lua_pushstring(L, "invalid param");
		return 2;
	}

	eproto_type proto_type = eproto_type::proto_rpc;
	if (lua_gettop(L) >= 3) {
		proto_type = (eproto_type)lua_tointeger(L, 3);
		if (proto_type < eproto_type::proto_rpc || proto_type >= eproto_type::proto_max) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid proto_type");
			return 2;
		}
	}

	std::string err;
	int token = m_mgr->listen(err, ip, port, proto_type);
	if (token == 0) {
		lua_pushnil(L);
		lua_pushstring(L, err.c_str());
		return 2;
	}

	auto listener = new lua_socket_node(token, m_lvm, m_mgr, m_archiver, m_router, true, proto_type);
	lua_push_object(L, listener);
	lua_pushstring(L, "ok");
	return 2;
}

int lua_socket_mgr::connect(lua_State* L) {
	// 获取参数个数
	int lua_param_count = lua_gettop(L);

	const char* ip = lua_tostring(L, 1);
	const char* port = lua_tostring(L, 2);
	int timeout = (int)lua_tonumber(L, 3);
	eproto_type proto_type = eproto_type::proto_rpc;

	// 如果有提供协议类型，需要设置协议类型
	if (lua_param_count >= 4) {
		proto_type = (eproto_type)(int)lua_tonumber(L, 4);
		if (proto_type < eproto_type::proto_rpc || proto_type >= eproto_type::proto_max) {
			lua_pushnil(L);
			lua_pushstring(L, "invalid proto_type");
			return 2;
		}
	}

	if (ip == nullptr || port == nullptr) {
		lua_pushnil(L);
		lua_pushstring(L, "invalid param");
		return 2;
	}

	std::string err;
	int token = m_mgr->connect(err, ip, port, timeout, proto_type);
	if (token == 0) {
		lua_pushnil(L);
		lua_pushstring(L, err.c_str());
		return 2;
	}

	auto stream = new lua_socket_node(token, m_lvm, m_mgr, m_archiver, m_router, false, proto_type);
	lua_push_object(L, stream);
	lua_pushstring(L, "ok");
	return 2;
}

void lua_socket_mgr::set_package_size(size_t size) {
	m_archiver->set_buffer_size(size);
}

void lua_socket_mgr::set_lz_threshold(size_t size) {
	m_archiver->set_lz_threshold(size);
}

void lua_socket_mgr::set_master(uint32_t group_idx, uint32_t token) {
	m_router->set_master(group_idx, token);
}

int lua_socket_mgr::map_token(lua_State* L) {
	uint32_t service_id = (uint32_t)lua_tointeger(L, 1);
	uint32_t token = (uint32_t)lua_tointeger(L, 2);
	uint16_t hash = (uint16_t)lua_tointeger(L, 3);
	m_router->map_token(service_id, token, hash);
	return 0;
}

void lua_socket_mgr::set_rpc_key(std::string key) {
	m_mgr->set_handshake_verify(key);
}