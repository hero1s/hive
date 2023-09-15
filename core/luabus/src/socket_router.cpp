#include "stdafx.h"
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <algorithm>
#include "fmt/core.h"
#include "socket_router.h"

uint32_t socket_router::map_token(uint32_t node_id, uint32_t token, uint16_t hash) {
	uint32_t group_idx = get_group_idx(node_id);
	auto& group = m_groups[group_idx];
	if (group.hash < hash) {
		//启动hash模式
		group.hash = hash;
	}
	if (token == 0) {
		group.mp_nodes.erase(node_id);
	}
	else {
		auto node = std::make_shared<service_node>();
		node->id = node_id;
		node->token = token;
		node->index = get_node_index(node_id);
		group.mp_nodes[node_id] = node;
	}
	flush_hash_node(group_idx);
	//掉线路由节点
	if (group_idx == m_router_idx && token == 0) {
		map_router_node(node_id, 0, 0);
	}
	return choose_master(group_idx);
}

uint32_t socket_router::set_node_status(uint32_t node_id, uint8_t status) {
	uint32_t group_idx = get_group_idx(node_id);
	auto& group = m_groups[group_idx];
	auto pTarget = group.get_target(node_id);
	if (pTarget != nullptr && pTarget->status != status) {		
		pTarget->status = status;
		flush_hash_node(group_idx);
		return choose_master(group_idx);		
	}
	return 0;
}

void socket_router::set_service_name(uint32_t service_id, std::string service_name) {
	m_service_names[service_id] = service_name;
}

void socket_router::map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status) {
	if (router_id == m_node_id)return;
	if (get_group_idx(router_id) != m_router_idx) {
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
	m_router_idx = get_group_idx(node_id);
	m_node_id = node_id;
}

uint32_t socket_router::choose_master(uint32_t group_idx) {
	if (group_idx < m_groups.size()) {
		auto& group = m_groups[group_idx];
		if (group.mp_nodes.empty()) {
			group.master = nullptr;
			return 0;
		}
		for (auto& [id, node] : group.mp_nodes) {
			if (node->status == 0) {
				group.master = node;
				return group.master->id;
			}
		}
	}
	return 0;
}

void socket_router::flush_hash_node(uint32_t group_idx) {
	if (group_idx < m_groups.size()) {
		auto& group = m_groups[group_idx];
		if (group.hash > 0) {//固定hash
			group.hash_ids.resize(group.hash);
			for (uint16_t i = 0; i < group.hash; ++i) {
				group.hash_ids[i] = build_service_id(group_idx, i + 1);
			}
		} else {
			group.hash_ids.clear();
			for (const auto& [id,node] : group.mp_nodes) {
				if (node->status == 0) {
					group.hash_ids.push_back(id);
				}				
			}
			std::sort(group.hash_ids.begin(),group.hash_ids.end());
		}
	}
}

bool socket_router::do_forward_target(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint64_t target_id = header->target_id;
	uint32_t group_idx = get_group_idx(target_id);
	auto& group = m_groups[group_idx];
	auto pTarget = group.get_target(target_id);
	if (pTarget == nullptr) {
		error = fmt::format("router[{}] forward-target not find,target:{}", cur_index(), get_service_nick(target_id));
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_target, target_id, 0);
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	m_mgr->sendv(pTarget->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_master(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint32_t group_idx = header->target_id;
	if (group_idx >= m_groups.size()) {
		error = fmt::format("router[{}] forward-master not decode", cur_index());
		return false;
	}
	auto master = m_groups[group_idx].master;
	if (master == nullptr) {
		error = fmt::format("router[{}] forward-master:{} token=0", cur_index(),get_service_name(group_idx));
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_master, 0, group_idx);
	}
	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	m_mgr->sendv(master->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num) {
	uint32_t group_idx = header->target_id;
	if (group_idx >= m_groups.size())
		return false;

	header->msg_id = (uint8_t)rpc_type::remote_call;
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };

	auto& group = m_groups[group_idx];
	for (auto& [id,target] : group.mp_nodes) {
		if (target->token != 0 && target->token != source) {
			m_mgr->sendv(target->token, items, _countof(items));
			broadcast_num++;
		}
	}
	return broadcast_num > 0;
}

bool socket_router::do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint16_t hash = header->target_id & 0xffff;
	uint16_t group_idx = header->target_id >> 16 & 0xffff;
	if (group_idx >= m_groups.size()) {
		error = fmt::format("router[{}] forward-hash not decode group", cur_index());
		return false;
	}
	auto& group = m_groups[group_idx];
	auto pTarget = group.hash_target(hash);
	if (pTarget != nullptr) {
		header->msg_id = (uint8_t)rpc_type::remote_call;
		sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
		m_mgr->sendv(pTarget->token, items, _countof(items));
		return true;
	} else {
		error = fmt::format("router[{}] forward-hash not nodes:{},hash:{}", cur_index(), get_service_name(group_idx),hash);
		return router ? false : do_forward_router(header, data, data_len, error, rpc_type::forward_hash, 0, group_idx);
	}
}

bool socket_router::do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid, uint64_t target_id, uint16_t group_idx)
{
	auto router_id = find_transfer_router(target_id, group_idx);
	if (router_id == 0) {
		error += fmt::format(" | not router can find:{},{}",get_service_nick(target_id),get_service_name(group_idx));
		return false;
	}
	auto ptarget = m_groups[m_router_idx].get_target(router_id);
	if (ptarget == nullptr) {
		error += fmt::format(" | not this router:{},{},{}",get_service_nick(router_id),get_service_nick(target_id),get_service_name(group_idx));
		return false;
	}
	header->msg_id = (uint8_t)msgid + (uint8_t)rpc_type::forward_router;	
	sendv_item items[] = { {header, sizeof(router_header)}, {data, data_len} };
	if (ptarget->token != 0) {
		m_mgr->sendv(ptarget->token, items, _countof(items));
		std::cout << fmt::format("forward router:{} msg:{},{},data_len:{}",ptarget->index,get_service_nick(target_id),get_service_name(group_idx),data_len) << std::endl;
		return true;
	}
	error += fmt::format(" | all router is disconnect");
	return false;
}

//轮流负载转发
uint32_t socket_router::find_transfer_router(uint32_t target_id, uint16_t group_idx) {
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
	if (group_idx > 0) {
		for (auto it = m_router_iter; it != m_routers.end(); it++) {
			if (it->second->groups.find(group_idx) != it->second->groups.end()) {
				m_router_iter = it;
				return it->first;
			}
		}
		for (auto it = m_routers.begin(); it != m_router_iter; it++) {
			if (it->second->groups.find(group_idx) != it->second->groups.end()) {
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
	auto service_id = get_group_idx(target_id);
	auto index = get_node_index(target_id);
	return fmt::format("{}_{}", get_service_name(service_id), index);
}