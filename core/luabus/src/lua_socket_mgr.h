#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "lua_archiver.h"
#include "socket_router.h"

struct lua_socket_mgr final
{
public:
	~lua_socket_mgr() {};
	bool setup(lua_State* L, uint32_t max_fd);
	int wait(int ms) { return m_mgr->wait(ms); }
	int listen(lua_State* L, const char* ip, int port);
	int connect(lua_State* L, const char* ip, const char* port, int timeout);
	void set_package_size(size_t size);
	int map_token(uint32_t node_id, uint32_t token, uint16_t hash);
	int set_node_status(uint32_t node_id, uint8_t status);
	void map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status);
	void map_player(uint32_t player_id, uint32_t lobby_id);
	void set_router_id(int id);
	void set_rpc_key(std::string key);
	const std::string get_rpc_key();


private:
	lua_State* m_lvm = nullptr;
	std::shared_ptr<socket_mgr> m_mgr;
	std::shared_ptr<lua_archiver> m_archiver;
	std::shared_ptr<socket_router> m_router;
};

