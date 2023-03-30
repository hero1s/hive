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

void socket_router::set_router_id(uint32_t node_id) {
	m_router_idx = get_group_idx(node_id);
	m_index = get_node_index(node_id);
}

void socket_router::set_service_status(uint16_t group_idx,uint16_t status) {
	if (group_idx < m_groups.size()) {
		m_groups[group_idx].status = status;
	}
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
	offset += encode_u64(header_data + offset, data_len - offset, header->router_id);
	return offset;
}

bool socket_router::do_forward_target(router_header* header, char* data, size_t data_len, std::string& error) {
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
		error = fmt::format("router forward-target not find,target_id:{}, group:{},index:{},status:{}", target_id, group_idx, get_node_index(target_id),group.status);
		if (group.status == 1 && verify_index(get_node_index(target_id))) {
			return do_forward_router(header, data - len, data_len + len, error, rpc_type::forward_target, group_idx, get_node_index(target_id));
		}
		return false;
	}

	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, rpc_type::remote_call);

	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };
	m_mgr->sendv(it->token, items, _countof(items));
	return true;
}

bool socket_router::do_forward_master(router_header* header, char* data, size_t data_len, std::string& error) {
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
		error = fmt::format("router forward-master:{},status:{} token=0",group_idx, m_groups[group_idx].status);
		if (m_groups[group_idx].status == 1) {
			return do_forward_router(header, data - len, data_len + len, error, rpc_type::forward_master, group_idx, 0);
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

bool socket_router::do_forward_hash(router_header* header, char* data, size_t data_len, std::string& error) {
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
		error = fmt::format("router forward-hash not nodes:{},status:{}",group_idx,group.status);
		if (group.status == 1) {
			return do_forward_router(header, data - hlen - glen, data_len + hlen + glen, error, rpc_type::forward_hash, group_idx, hash);
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

bool socket_router::do_forward_router(router_header* header, char* data, size_t data_len, std::string& error, rpc_type msgid, uint64_t target_idx, uint64_t target_index)
{
	if (m_router_idx < 0 || m_router_idx > m_groups.size()) {
		error += fmt::format(" | router idx is error:{}",m_router_idx);
		return false;
	}
	auto& router_group = m_groups[m_router_idx];
	auto& nodes = router_group.nodes;
	int count = (int)nodes.size();
	if (count == 0) {
		error += fmt::format(" | router group is empty:{}",m_router_idx);
		return false;
	}
	uint16_t start_index = header->router_id >> 16;
	uint16_t last_index = header->router_id & 0x3ff;
	service_node* ptarget = nullptr;
	if (start_index == 0) {
		start_index = m_index;
		last_index = m_index;
	}
	uint16_t flag = start_index >> 10;
	if (flag == 0) {
		for (auto& node : nodes) {
			if (node.index > start_index && node.index > last_index) {
				last_index = node.index;
				ptarget = &node;
				break;
			}
		}
		if (ptarget == nullptr) {//后位已空
			flag = 1;
			start_index = 1 << 10 | start_index;
		}
	}
	if (flag == 1) {
		uint16_t t_index = start_index & 0x3ff;
		if (last_index >= t_index) {//首次重置
			last_index = 0;
		}
		for (auto& node : nodes) {
			if (node.index < t_index && node.index > last_index) {
				last_index = node.index;
				ptarget = &node;
				break;
			}
		}
	}
	if (ptarget == nullptr) {//已经轮完
		error += fmt::format(" | router had run over:{}", nodes.size());
		return false;
	}
	header->router_id = start_index << 16 | last_index;

	size_t header_len = format_header(m_header_data, sizeof(m_header_data), header, (rpc_type)((uint8_t)msgid + (uint8_t)rpc_type::forward_router));
	sendv_item items[] = { {m_header_data, header_len}, {data, data_len} };

	if (ptarget->token != 0) {
		m_mgr->sendv(ptarget->token, items, _countof(items));
		return true;
	}
	error += fmt::format(" | all router is disconnect");
	return false;
}

