#pragma once
#include <memory>
#include <array>
#include <vector>
#include "var_int.h"
#include "socket_mgr.h"
#include "socket_helper.h"

enum class rpc_type : uint8_t {
	remote_call,
	forward_target,
	forward_master,
	forward_broadcast,
	forward_hash,
	forward_router,
};

const int MAX_SERVICE_GROUP = 255;

struct service_node {
	uint32_t id		= 0;
	uint32_t token  = 0;
	uint16_t index  = 0;
};

constexpr int ROUTER_HEAD_LEN = MAX_VARINT_SIZE * 4;

struct router_header {
	uint64_t rpc_flag   = 0;
	uint64_t source_id  = 0;
	uint64_t session_id = 0;
	uint64_t router_id  = 0;
};

struct service_group {
	uint16_t hash = 0;
	service_node master;
	std::vector<service_node> nodes;
};

class socket_router
{
public:
	socket_router(std::shared_ptr<socket_mgr>& mgr) : m_mgr(mgr) { }

	uint32_t map_token(uint32_t node_id, uint32_t token, uint16_t hash);
	void set_router_id(uint32_t node_id);
	uint32_t choose_master(uint32_t service_id);
	void erase(uint32_t node_id);
	bool do_forward_target(router_header* header, char* data, size_t data_len, std::string& error);
	bool do_forward_master(router_header* header, char* data, size_t data_len, std::string& error);
	bool do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num);
	bool do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error);
	size_t format_header(BYTE* header_data, size_t data_len, router_header* header, rpc_type msgid);

	bool do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid,uint64_t target_idx, uint64_t target_index);

	std::string debug_header(router_header* header);
private:
	std::shared_ptr<socket_mgr> m_mgr;
	std::array<service_group, MAX_SERVICE_GROUP> m_groups;
	int16_t m_router_idx = -1;
	uint16_t m_index = 0;
	BYTE m_header_data[ROUTER_HEAD_LEN];
};

