#include "stdafx.h"
#include "var_int.h"
#include "lua_socket_mgr.h"
#include "lua_socket_node.h"

// 64M
constexpr int LUA_AR_BUFFER_SIZE = 64 * 1024 * 1024;

bool lua_socket_mgr::setup(lua_State* L, uint32_t max_fd) {
	m_lvm = L;
	m_mgr = std::make_shared<socket_mgr>();
	m_archiver = std::make_shared<lua_archiver>(LUA_AR_BUFFER_SIZE);
	m_router = std::make_shared<socket_router>(m_mgr);
	return m_mgr->setup(max_fd);
}

int lua_socket_mgr::listen(lua_State* L, const char* ip, int port) {
	if (ip == nullptr || port <= 0) {
		return luakit::variadic_return(L, nullptr, "invalid param");
	}
	std::string err;
	eproto_type proto_type = (eproto_type)luaL_optinteger(L, 3, 0);
	auto token = m_mgr->listen(err, ip, port, proto_type);
	if (token == 0) {
		return luakit::variadic_return(L, nullptr, err);
	}

	auto listener = new lua_socket_node(token, m_lvm, m_mgr, m_archiver, m_router, true, proto_type);
	return luakit::variadic_return(L, listener, "ok");
}

int lua_socket_mgr::connect(lua_State* L, const char* ip, const char* port, int timeout) {
	if (ip == nullptr || port == nullptr) {
		return luakit::variadic_return(L, nullptr, "invalid param");
	}

	std::string err;
	eproto_type proto_type = (eproto_type)luaL_optinteger(L, 4, 0);
	auto token = m_mgr->connect(err, ip, port, timeout, proto_type);
	if (token == 0) {
		return luakit::variadic_return(L, nullptr, err);
	}

	auto stream = new lua_socket_node(token, m_lvm, m_mgr, m_archiver, m_router, false, proto_type);
	return luakit::variadic_return(L, stream, "ok");
}

void lua_socket_mgr::set_package_size(size_t size) {
	m_archiver->set_buffer_size(size);
}

int lua_socket_mgr::map_token(uint32_t node_id, uint32_t token,uint16_t hash) {
	return m_router->map_token(node_id, token, hash);
}

int lua_socket_mgr::set_node_status(uint32_t node_id, uint8_t status) {
	return m_router->set_node_status(node_id, status);
}

void lua_socket_mgr::map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status) {
	return m_router->map_router_node(router_id,target_id,status);
}

void lua_socket_mgr::map_player(uint32_t player_id, uint32_t lobby_id) {
	return m_router->map_player(player_id, lobby_id);
}

void lua_socket_mgr::set_router_id(int id) {
	m_router->set_router_id(id);
}

void lua_socket_mgr::set_rpc_key(std::string key) {
	m_mgr->set_handshake_verify(key);
}

const std::string lua_socket_mgr::get_rpc_key() {
	return m_mgr->get_handshake_verify();
}

