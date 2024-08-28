#include "stdafx.h"
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <algorithm>
#include "fmt/core.h"
#include "socket_router.h"

uint32_t socket_router::map_token(uint32_t node_id, uint32_t token, uint16_t hash) {
	auto service_id = get_service_id(node_id);
	auto group = get_node_group(node_id);
	auto& services = m_services[service_id];
	if (services.hash < hash) {
		//启动hash模式
		services.hash = hash;
	}
	if (token == 0) {
		services.mp_nodes.erase(node_id);
	}
	else {
		auto node = std::make_shared<service_node>();
		node->id = node_id;
		node->token = token;
		node->index = get_node_index(node_id);
		node->group = get_node_group(node_id);
		services.mp_nodes[node_id] = node;
	}
	flush_hash_node(group, service_id);
	//掉线路由节点
	if (service_id == m_router_idx && token == 0) {
		map_router_node(node_id, 0, 0);
	}
	return choose_master(service_id);
}

uint32_t socket_router::hash_value(uint32_t service_id) {
	if (service_id < m_services.size()) {
		return m_services[service_id].hash;	
	}
	return 0;
}

uint32_t socket_router::set_node_status(uint32_t node_id, uint8_t status) {
	auto service_id = get_service_id(node_id);
	auto group = get_node_group(node_id);
	auto& services = m_services[service_id];
	auto pTarget = services.get_target(node_id);
	if (pTarget != nullptr && pTarget->status != status) {		
		pTarget->status = status;
		flush_hash_node(group, service_id);
		return choose_master(service_id);		
	}
	return 0;
}

void socket_router::set_service_name(uint32_t service_id, std::string service_name) {
	m_service_names[service_id] = service_name;
}

void socket_router::map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status) {
	if (router_id == m_node_id)return;
	if (get_service_id(router_id) != m_router_idx) {
		std::cout << "error router_id:" << router_id << std::endl;
		return;
	}
	auto it = m_routers.find(router_id);
	if (it != m_routers.end()) {
		if (target_id == 0) {//清空
			m_router_iter = m_routers.erase(it);
			return;
		}
		if (status == 0) {
			it->second->targets.erase(target_id);
		} else {
			it->second->targets.insert(target_id);
		}
		it->second->flush_group();
	} else {
		if (status != 0) {
			auto node = std::make_shared<router_node>();
			node->id = router_id;
			node->targets.insert(target_id);
			node->flush_group();
			m_routers.insert(std::pair(node->id, node));
			m_router_iter = m_routers.begin();
		}
	}
}

void socket_router::set_router_id(uint32_t node_id) {
	m_router_idx = get_service_id(node_id);
	m_node_id = node_id;
}

uint32_t socket_router::choose_master(uint32_t service_id) {
	if (service_id < m_services.size()) {
		auto& services = m_services[service_id];
		if (services.mp_nodes.empty()) {
			services.master = nullptr;
			return 0;
		}
		for (auto& [id, node] : services.mp_nodes) {
			if (node->status == 0) {
				services.master = node;
				return services.master->id;
			}
		}
	}
	return 0;
}

void socket_router::flush_hash_node(uint16_t group, uint32_t service_id) {
	if (service_id < m_services.size()) {
		auto& services = m_services[service_id];
		if (services.hash > 0) {//固定hash
			services.hash_ids.resize(services.hash);
			for (uint16_t i = 0; i < services.hash; ++i) {
				services.hash_ids[i] = build_service_id(group, service_id, i + 1);
			}
		} else {
			services.hash_ids.clear();
			for (const auto& [id,node] : services.mp_nodes) {
				if (node->status == 0) {
					services.hash_ids.push_back(id);
				}				
			}
			std::sort(services.hash_ids.begin(), services.hash_ids.end());
		}
	}
}

bool socket_router::do_forward_target(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	auto target_id = header->target_sid;
	auto service_id = get_service_id(target_id);
	auto& services = m_services[service_id];
	auto pTarget = services.get_target(target_id);
	if (pTarget == nullptr) {
		error = fmt::format("router[{}] forward-target not find,target:{}", cur_index(), get_service_nick(target_id));
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_target, target_id, 0);
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	m_mgr->sendv(pTarget->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_player(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint32_t service_id = header->target_sid;
	uint32_t player_id = header->target_pid;
	uint32_t target_id = find_player_sid(player_id, service_id);
	if (target_id == 0) {
		error = fmt::format("router[{}] forward-player not find player:{} service:{}", cur_index(), player_id, get_service_name(service_id));
		return false;
	}
	auto& services = m_services[service_id];
	auto pTarget = services.get_target(target_id);
	if (pTarget == nullptr) {
		error = fmt::format("router[{}] forward-player not find,target:{}", cur_index(), get_service_nick(target_id));
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_target, target_id, 0);
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	m_mgr->sendv(pTarget->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_group_player(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	data = decode_player_ids(bus_ids, data, &data_len);
	uint32_t service_id = header->target_sid;
	m_target_ids.clear();
	for (auto player_id : bus_ids) {
		uint32_t target_id = find_player_sid(player_id, service_id);
		if (target_id != 0) {
			m_target_ids.insert(target_id);
		}
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	header->len = data_len + sizeof(router_header);
	auto& services = m_services[service_id];
	for (auto target_id : m_target_ids) {
		auto pTarget = services.get_target(target_id);
		if (pTarget != nullptr) {			
			sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
			m_mgr->sendv(pTarget->token, items, _countof(items));
		}
	}
	return true;
}

bool socket_router::do_forward_master(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint32_t service_id = header->target_sid;
	if (service_id >= m_services.size()) {
		error = fmt::format("router[{}] forward-master not decode", cur_index());
		return false;
	}
	auto master = m_services[service_id].master;
	if (master == nullptr) {
		error = fmt::format("router[{}] forward-master:{} token=0", cur_index(),get_service_name(service_id));
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_master, 0, service_id);
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	m_mgr->sendv(master->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num) {
	uint32_t service_id = header->target_sid;
	if (service_id >= m_services.size())
		return false;

	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };

	auto& group = m_services[service_id];
	for (auto& [id,target] : group.mp_nodes) {
		if (target->token != 0 && target->token != source) {
			m_mgr->sendv(target->token, items, _countof(items));
			broadcast_num++;
		}
	}
	return true;
}

bool socket_router::do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint16_t hash = header->target_pid;
	uint16_t service_id = header->target_sid;
	if (service_id >= m_services.size()) {
		error = fmt::format("router[{}] forward-hash not decode group", cur_index());
		return false;
	}
	auto& services = m_services[service_id];
	auto pTarget = services.hash_target(hash);
	if (pTarget != nullptr) {
		header->msg_id = (uint8_t)rpc_type::remote_call;
		sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
		m_mgr->sendv(pTarget->token, items, _countof(items));
		return true;
	} else {
		error = fmt::format("router[{}] forward-hash not nodes:{},hash:{}", cur_index(), get_service_name(service_id),hash);
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_hash, 0, service_id);
	}
}

bool socket_router::do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid, uint64_t target_id, uint16_t service_id)
{
	auto router_id = find_transfer_router(target_id, service_id);
	if (router_id == 0) {
		error += fmt::format(" | not router can find:{},{}",get_service_nick(target_id),get_service_name(service_id));
		return false;
	}
	auto ptarget = m_services[m_router_idx].get_target(router_id);
	if (ptarget == nullptr) {
		error += fmt::format(" | not this router:{},{},{}",get_service_nick(router_id),get_service_nick(target_id),get_service_name(service_id));
		return false;
	}
	header->msg_id = (uint8_t)msgid + (uint8_t)rpc_type::forward_router;	
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	if (ptarget->token != 0) {
		m_mgr->sendv(ptarget->token, items, _countof(items));
		//std::cout << fmt::format("forward router:{} msg:{},{},data_len:{}",ptarget->index,get_service_nick(target_id),get_service_name(service_id),data_len) << std::endl;
		return true;
	}
	error += fmt::format(" | all router is disconnect");
	return false;
}

//玩家路由
void socket_router::set_player_service(uint32_t player_id, uint32_t sid, uint8_t login) {
	auto service_id = get_service_id(sid);
	if (service_id >= m_players.size()) {		
		return;
	}
	auto& players = m_players[service_id];
	if (login == 0) {
		players.set_player_service(player_id, 0);
	} else {
		players.set_player_service(player_id, sid);
	}	
}
uint32_t socket_router::find_player_sid(uint32_t player_id, uint16_t service_id) {
	if (service_id >= m_players.size()) {
		return 0;
	}
	auto& players = m_players[service_id];
	return players.find_player_sid(player_id);
}
void socket_router::clean_player_sid(uint32_t sid) {
	auto service_id = get_service_id(sid);
	if (service_id >= m_players.size()) {
		return;
	}
	auto& players = m_players[service_id];
	players.clean_sid(sid);
}

//序列化玩家id
void* socket_router::encode_player_ids(std::vector<uint32_t>& player_ids, size_t* len) {	
	m_buf.clean();
	m_buf.write((uint8_t)player_ids.size());
	for (auto id : player_ids) {
		m_buf.write(id);
	}
	return m_buf.data(len);
}
char* socket_router::decode_player_ids(std::vector<uint32_t>& player_ids, char* data, size_t* data_len) {
	player_ids.clear();
	auto s = slice((uint8_t*)data, *data_len);
	auto num = *s.read<uint8_t>();
	for (uint8_t i = 0; i < num; i++) {
		player_ids.push_back(*s.read<uint32_t>());
	}
	return (char*)s.data(data_len);
}

//轮流负载转发
uint32_t socket_router::find_transfer_router(uint32_t target_id, uint16_t service_id) {
	if (m_router_iter != m_routers.end()) {
		m_router_iter++;
	} else {
		m_router_iter = m_routers.begin();
	}
	if (target_id > 0) {
		for (auto it = m_router_iter; it != m_routers.end();it++) {
			if (it->second->targets.find(target_id) != it->second->targets.end()) {
				m_router_iter = it;
				return it->first;
			}
		}
		for (auto it = m_routers.begin(); it != m_router_iter; it++) {
			if (it->second->targets.find(target_id) != it->second->targets.end()) {
				m_router_iter = it;
				return it->first;
			}
		}
		return 0;
	}
	if (service_id > 0) {
		for (auto it = m_router_iter; it != m_routers.end(); it++) {
			if (it->second->groups.find(service_id) != it->second->groups.end()) {
				m_router_iter = it;
				return it->first;
			}
		}
		for (auto it = m_routers.begin(); it != m_router_iter; it++) {
			if (it->second->groups.find(service_id) != it->second->groups.end()) {
				m_router_iter = it;
				return it->first;
			}
		}
	}
	return 0;
}

std::string socket_router::get_service_name(uint32_t service_id) {
	auto it = m_service_names.find(service_id);
	if (it != m_service_names.end()) {
		return it->second;
	}
	return fmt::format("{}", service_id);
}
std::string socket_router::get_service_nick(uint32_t target_id) {
	auto service_id = get_service_id(target_id);
	auto group = get_node_group(target_id);
	auto index = get_node_index(target_id);
	return fmt::format("{}_{}_{}", get_service_name(service_id), group, index);
}