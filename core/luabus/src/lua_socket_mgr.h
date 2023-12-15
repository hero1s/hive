#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "socket_router.h"

struct lua_socket_mgr final
{
public:
	~lua_socket_mgr() {};
	bool setup(lua_State* L, uint32_t max_fd);
	int wait(int ms) { return m_mgr->wait(ms); }
	int listen(lua_State* L, const char* ip, int port);
	int connect(lua_State* L, const char* ip, const char* port, int timeout);
	int map_token(uint32_t node_id, uint32_t token, uint16_t hash);
	int set_node_status(uint32_t node_id, uint8_t status);
	void map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status);
	void set_router_id(int id);
	void set_service_name(uint32_t service_id, std::string service_name);
	void set_rpc_key(std::string key);
	const std::string get_rpc_key();
	int broadgroup(lua_State* L, codec_base* codec);

	//Íæ¼ÒÂ·ÓÉ
	void set_player_service(uint32_t player_id, uint32_t sid, uint8_t login);
	uint32_t find_player_sid(uint32_t player_id, uint16_t service_id);
	void clean_player_sid(uint32_t sid);
private:
	stdsptr<kit_state> m_luakit = nullptr;
	stdsptr<socket_mgr> m_mgr;
	codec_base* m_codec = nullptr;
	stdsptr<socket_router> m_router;
};

