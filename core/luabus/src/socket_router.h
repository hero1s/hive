#pragma once
#include <memory>
#include <array>
#include <vector>
#include <set>
#include "socket_mgr.h"
#include "socket_helper.h"

static thread_local std::vector<uint32_t> bus_ids;

enum class rpc_type : uint8_t {
	remote_call,
	forward_target,
	forward_master,
	forward_broadcast,
	forward_hash,
	forward_player,
	forward_group_player,
	forward_router,//must be max 	
};

const int MAX_SERVICE_GROUP = (UCHAR_MAX + 1);
inline uint16_t get_service_id(uint32_t node_id) { return  (node_id >> 16) & 0xff; }
inline uint16_t get_node_group(uint32_t node_id) { return node_id >> 26; }
inline uint16_t get_node_index(uint32_t node_id) { return node_id & 0xfff; }
inline uint32_t build_service_id(uint16_t group, uint16_t service_id, uint16_t index) { return group << 26 | (service_id & 0xff) << 16 | index; }

struct service_node {
	uint32_t id		= 0;
	uint32_t token  = 0;
	uint16_t index  = 0;
	uint8_t  group  = 0;
	uint8_t  status = 0;
};

struct router_node {
	uint32_t id			= 0;//路由服id
	std::set<uint32_t> targets;//目标节点
	std::set<uint16_t> groups; //目标组
	inline void flush_group() {
		groups.clear();
		for (auto it : targets) {
			groups.insert(get_service_id(it));
		}
	}
};

#pragma pack(1)
struct router_header {
	uint8_t  msg_id		= 0;
	uint8_t  rpc_flag   = 0;
	uint32_t len		= 0;
	uint32_t source_id  = 0;
	uint32_t session_id = 0;
	uint32_t target_sid = 0;
	uint32_t target_pid = 0;
};
#pragma pack()

struct service_list {
	uint16_t hash = 0;
	stdsptr<service_node> master = nullptr;
	std::vector<uint32_t> hash_ids;
	std::unordered_map<uint32_t, stdsptr<service_node>> mp_nodes;
	inline stdsptr<service_node> get_target(uint32_t id) {
		auto it = mp_nodes.find(id);
		if (it != mp_nodes.end()) {
			return it->second;
		}
		return nullptr;
	}
	inline stdsptr<service_node> hash_target(uint64_t hash) {
		auto count = hash_ids.size();
		if (count > 0) {
			auto id = hash_ids[hash % count];
			auto it = mp_nodes.find(id);
			if (it != mp_nodes.end()) {
				return it->second;
			}
		}
		return nullptr;
	}
};

struct player_list
{
	std::unordered_map<uint32_t, uint32_t> mp_player_sid;
	inline void set_player_service(uint32_t player_id, uint32_t sid) {
		if (sid > 0) {
			mp_player_sid[player_id] = sid;
		} else {
			mp_player_sid.erase(player_id);
		}
	}
	inline uint32_t find_player_sid(uint32_t player_id) {
		auto it = mp_player_sid.find(player_id);
		return it != mp_player_sid.end() ? it->second : 0;
	}
	inline void clean_sid(uint32_t sid) {
		for (auto it = mp_player_sid.begin(); it != mp_player_sid.end();) {
			if (it->second == sid) {
				it = mp_player_sid.erase(it);
			} else {
				++it;
			}
		}
	}
};

class socket_router
{
public:
	socket_router(stdsptr<socket_mgr>& mgr) : m_mgr(mgr) { }

	uint32_t map_token(uint32_t node_id, uint32_t token, uint16_t hash);
	uint32_t hash_value(uint32_t service_id);
	uint32_t set_node_status(uint32_t node_id, uint8_t status);
	void set_service_name(uint32_t service_id, std::string service_name);
	void map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status);	
	void set_router_id(uint32_t node_id);
	uint32_t choose_master(uint32_t service_id);
	void flush_hash_node(uint16_t group, uint32_t service_id);

	bool do_forward_target(router_header* header, char* data, size_t data_len, std::string& error, bool router);
	bool do_forward_player(router_header* header, char* data, size_t data_len, std::string& error, bool router);
	bool do_forward_group_player(router_header* header, char* data, size_t data_len, std::string& error, bool router);
	bool do_forward_master(router_header* header, char* data, size_t data_len, std::string& error, bool router);
	bool do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num);
	bool do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error, bool router);	

	bool do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid,uint64_t target_id, uint16_t service_id);

	//玩家路由
	void set_player_service(uint32_t player_id, uint32_t sid, uint8_t login);
	uint32_t find_player_sid(uint32_t player_id, uint16_t service_id);
	void clean_player_sid(uint32_t sid);
	//序列化玩家id
	void* encode_player_ids(std::vector<uint32_t>& player_ids, size_t* len);
	char* decode_player_ids(std::vector<uint32_t>& player_ids, char* data, size_t* data_len);

protected:
	uint32_t find_transfer_router(uint32_t target_id, uint16_t service_id);
	uint16_t cur_index() { return get_node_index(m_node_id); };
	std::string get_service_name(uint32_t service_id);
	std::string get_service_nick(uint32_t target_id);

private:
	stdsptr<socket_mgr> m_mgr;
	std::unordered_map<uint32_t, std::string> m_service_names;
	std::array<service_list, MAX_SERVICE_GROUP> m_services{};
	std::array<player_list, MAX_SERVICE_GROUP> m_players{};
	std::unordered_map<uint32_t, stdsptr<router_node>> m_routers;
	std::unordered_map<uint32_t, stdsptr<router_node>>::iterator m_router_iter = m_routers.begin();
	int16_t m_router_idx = -1;
	uint32_t m_node_id = 0;
	luabuf m_buf;
	//收集玩家指定服务所在id
	std::set<uint32_t> m_target_ids;
};

