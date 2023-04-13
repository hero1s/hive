#include "stdafx.h"
#include <stdlib.h>
#include <limits.h>
#include <string.h>
#include <algorithm>
#include "fmt/core.h"
#include "var_int.h"
#include "socket_router.h"

uint32_t get_group_idx(uint32_t node_id) { return  (node_id >> 16) & 0xff; }
uint32_t get_node_index(uint32_t node_id) { return node_id & 0x3ff; }
uint32_t build_service_id(uint16_t group_idx, uint16_t index) { return (group_idx & 0xff) << 16 | index; }
bool verify_index(uint16_t index) { return index > 0 && index < 0x3ff; }

bool comp_node(service_node& node, uint32_t id) { return node.id < id; }

uint32_t socket_router::map_token(uint32_t node_id, uint32_t token, uint16_t hash) {
	uint32_t group_idx = get_group_idx(node_id);
	auto& group = m_groups[group_idx];
	auto& nodes = group.nodes;
	if (group.hash < hash) {
		//启动hash模式
		group.hash = hash;
		nodes.resize(hash);
		for (uint16_t i = 0; i < hash; ++i) {
			if (nodes[i].id == 0) {
				nodes[i].id = build_service_id(group_idx, i + 1);
			}
		}
	}
	auto it = std::lower_bound(nodes.begin(), nodes.end(), node_id, comp_node);
	if (it != nodes.end() && it->id == node_id) {
		if (group.hash > 0 || token > 0) {
			it->token = token;
			return group.master.id;
		}
		nodes.erase(it);
		return choose_master(group_idx);
	}
	service_node node;
	node.id = node_id;
	node.token = token;
	node.index = get_node_index(node_id);
	nodes.insert(it, node);
	return choose_master(group_idx);
}

void socket_router::map_router_node(uint32_t router_id, uint32_t target_id, uint8_t status) {
	auto it = m_routers.find(router_id);
	if (it != m_routers.end()) {
		if (target_id == 0) {//清空
			m_routers.erase(it);
			return;
		}
		if (status == 0) {
			it->second.targets.erase(target_id);
			it->second.groups.erase(get_group_idx(target_id));
		} else {
			it->second.targets.insert(target_id);
			it->second.groups.insert(get_group_idx(target_id));
		}
	} else {
		if (status != 0) {
			router_node node;
			node.id = router_id;
			node.targets.insert(target_id);
			node.groups.insert(get_group_idx(target_id));
			m_routers.insert(std::pair(node.id, node));
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
		if (group.nodes.empty()) {
			group.master = service_node{};
			return 0;
		}
		group.master = group.nodes.front();
		return group.master.id;
	}
	return 0;
}

void socket_router::erase(uint32_t node_id) {
	uint32_t group_idx = get_group_idx(node_id);
	auto& group = m_groups[group_idx];
	auto& nodes = group.nodes;
	auto it = std::lower_bound(nodes.begin(), nodes.end(), node_id, comp_node);
	if (it != nodes.end() && it->id == node_id) {
		nodes.erase(it);
		choose_master(group_idx);
	}
}

size_t socket_router::format_header(BYTE* header_data, size_t data_len, router_header* header, rpc_type msgid) {
	size_t offset = 0;
	offset += encode_u64(header_data + offset, data_len - offset, (char)msgid);
	offset += encode_u64(header_data + offset, data_len - offset, header->session_id);
	offset += encode_u64(header_data + offset, data_len - offset, header->rpc_flag);
	offset += encode_u64(header_data + offset, data_len - offset, header->source_id);
	return offset;
}

bool socket_router::do_forward_target(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint64_t target_id = 0;
	size_t len = decode_u64(&target_id, (BYTE*)data, data_len);
	if (len == 0) {
		error = fmt::format("router forward-target not decode");
		return false;
	}
	data += len;
	data_len -= len;
	uint32_t group_idx = get_group_idx(target_id);
	auto& group = m_groups[group_idx];
	auto& nodes = group.nodes;
	auto it = std::lower_bound(nodes.begin(), nodes.end(), target_id, comp_node);
	if (it == nodes.end() || it->id != target_id) {
		error = fmt::format("router forward-target not find,target_id:{}, group:{},index:{}", target_id, group_idx, get_node_index(target_id));
		if (!router) {
			return do_forward_router(header, data - len, data_len + len, error, rpc_type::forward_target, target_id, group_idx);
		}
		return false;
	}
	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, rpc_type::remote_call);

	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };
	m_mgr->sendv(it->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_master(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint64_t group_idx = 0;
	size_t len = decode_u64(&group_idx, (BYTE*)data, data_len);
	if (len == 0 || group_idx >= m_groups.size()) {
		error = fmt::format("router forward-master not decode");
		return false;
	}

	data += len;
	data_len -= len;

	auto token = m_groups[group_idx].master.token;
	if (token == 0) {
		error = fmt::format("router forward-master:{} token=0",group_idx);
		if (!router) {
			return do_forward_router(header, data - len, data_len + len, error, rpc_type::forward_master, 0, group_idx);
		}
		return false;
	}

	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, rpc_type::remote_call);

	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };
	m_mgr->sendv(token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num) {
	uint64_t group_idx = 0;
	size_t len = decode_u64(&group_idx, (BYTE*)data, data_len);
	if (len == 0 || group_idx >= m_groups.size())
		return false;

	data += len;
	data_len -= len;

	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, rpc_type::remote_call);
	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };

	auto& group = m_groups[group_idx];
	auto& nodes = group.nodes;
	int count = (int)nodes.size();
	for (auto& target : nodes) {
		if (target.token != 0 && target.token != source) {
			m_mgr->sendv(target.token, items, _countof(items));
			broadcast_num++;
		}
	}
	return broadcast_num > 0;
}

bool socket_router::do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error, bool router) {
	uint64_t group_idx = 0;
	size_t glen = decode_u64(&group_idx, (BYTE*)data, data_len);
	if (glen == 0 || group_idx >= m_groups.size()) {
		error = fmt::format("router forward-hash not decode group");
		return false;
	}

	data += glen;
	data_len -= glen;

	uint64_t hash = 0;
	size_t hlen = decode_u64(&hash, (BYTE*)data, data_len);
	if (hlen == 0) {
		error = fmt::format("router forward-hash not decode hash");
		return false;
	}

	data += hlen;
	data_len -= hlen;

	auto& group = m_groups[group_idx];
	auto& nodes = group.nodes;
	int count = (int)nodes.size();
	if (count == 0) {
		error = fmt::format("router forward-hash not nodes:{}",group_idx);
		if (!router) {
			return do_forward_router(header, data - hlen - glen, data_len + hlen + glen, error, rpc_type::forward_hash, 0, group_idx);
		}
		return false;
	}

	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, rpc_type::remote_call);
	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };

	auto& target = nodes[hash % count];
	if (target.token != 0) {
		m_mgr->sendv(target.token, items, _countof(items));
		return true;
	}
	error = fmt::format("router forward-hash not token");
	return false;
}

bool socket_router::do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid, uint64_t target_id, uint16_t group_idx)
{
	auto router_id = find_transfer_router(target_id, group_idx);
	if (router_id == 0) {
		error += fmt::format(" | not router can find:{},{}", target_id,group_idx);
		return false;
	}
	auto& router_group = m_groups[m_router_idx];
	auto& nodes = router_group.nodes;
	int count = (int)nodes.size();
	if (count == 0) {
		error += fmt::format(" | router group is empty");
		return false;
	}
	service_node* ptarget = nullptr;
	for (auto& node : nodes) {
		if (node.id == router_id) {
			ptarget = &node;
			break;
		}
	}
	if (ptarget == nullptr) {
		error += fmt::format(" | not this router:{},{}", router_id, nodes.size());
		return false;
	}
	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, (rpc_type)((uint8_t)msgid + (uint8_t)rpc_type::forward_router));
	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };
	if (ptarget->token != 0) {
		m_mgr->sendv(ptarget->token, items, _countof(items));
		return true;
	}
	error += fmt::format(" | all router is disconnect");
	return false;
}

uint32_t socket_router::find_transfer_router(uint32_t target_id, uint16_t group_idx) {
	for (auto& it : m_routers) {
		if (it.first == m_node_id)continue;
		if (target_id > 0 && it.second.targets.find(target_id) != it.second.targets.end()) {
			return it.first;
		}
		if (group_idx > 0 && it.second.groups.find(group_idx) != it.second.groups.end()) {
			return it.first;
		}
	}
	return 0;
}

