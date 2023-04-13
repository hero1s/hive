#include "stdafx.h"
#include "fmt/core.h"
#include "var_int.h"
#include "lua_socket_node.h"
#include "socket_helper.h"
#include <iostream>

lua_socket_node::lua_socket_node(uint32_t token, lua_State* L, std::shared_ptr<socket_mgr>& mgr,
	std::shared_ptr<lua_archiver>& ar, std::shared_ptr<socket_router> router, bool blisten, eproto_type proto_type)
	: m_token(token), m_lvm(L), m_mgr(mgr), m_archiver(ar), m_router(router), m_proto_type(proto_type) {
	m_mgr->get_remote_ip(m_token, m_ip);

	if (blisten) {
		m_mgr->set_accept_callback(token, [=](uint32_t steam_token, eproto_type proto_type) {
			luakit::kit_state kit_state(m_lvm);
			auto stream = new lua_socket_node(steam_token, m_lvm, m_mgr, m_archiver, m_router, false, proto_type);
			kit_state.object_call(this, "on_accept", nullptr, std::tie(), stream);
			});
	}

	m_mgr->set_connect_callback(token, [=](bool ok, const char* reason) {
		if (ok) {
			m_mgr->get_remote_ip(m_token, m_ip);
		}
		luakit::kit_state kit_state(m_lvm);
		kit_state.object_call(this, "on_connect", nullptr, std::tie(), ok ? "ok" : reason);
		if (!ok) {
			this->m_token = 0;
		}
		});

	m_mgr->set_error_callback(token, [=](const char* err) {
		auto token = m_token;
		m_token = 0;
		luakit::kit_state kit_state(m_lvm);
		kit_state.object_call(this, "on_error", nullptr, std::tie(), token, err);
		});

	m_mgr->set_package_callback(token, [=](char* data, size_t data_len) {
		on_recv(data, data_len);
		});
}

lua_socket_node::~lua_socket_node() {
	close();
}

int lua_socket_node::call_pack(lua_State* L) {
	int top = lua_gettop(L);
	if (top < 4) {
		lua_pushinteger(L, -1);
		return 1;
	}

	socket_header header;
	header.cmd_id = lua_tointeger(L, 1);
	header.flag = lua_tointeger(L, 2);
	header.session_id = lua_tointeger(L, 3);
	header.seq_id = m_seq_id++;

	size_t data_len = 0;
	const char* data_ptr = lua_tolstring(L, 4, &data_len);
	if (data_len + sizeof(socket_header) >= NET_PACKET_MAX_LEN) {
		lua_pushinteger(L, -2);
		return 1;
	}
	header.len = data_len + sizeof(socket_header);

	sendv_item items[] = { { &header, sizeof(socket_header) }, {data_ptr, data_len} };
	auto send_len = m_mgr->sendv(m_token, items, _countof(items));

	lua_pushinteger(L, send_len);
	return 1;
}

int lua_socket_node::call_text(lua_State* L) {
	size_t data_len = 0;
	const char* data_ptr = lua_tolstring(L, 1, &data_len);
	auto send_len = m_mgr->send(m_token, data_ptr, data_len);
	lua_pushinteger(L, send_len);
	return 1;
}

int lua_socket_node::call_slice(slice* slice) {
	return m_mgr->send(m_token,(const char*)slice->head(), slice->size());
}

size_t lua_socket_node::format_header(lua_State* L, BYTE* header_data, size_t data_len, rpc_type msgid) {
	uint32_t offset = 0;
	router_header header;
	header.session_id = (uint32_t)lua_tointeger(L, 1);
	header.rpc_flag = (uint32_t)lua_tointeger(L, 2);
	header.source_id = (uint32_t)lua_tointeger(L, 3);
	return m_router->format_header(header_data, data_len, &header, msgid);
}

size_t lua_socket_node::parse_header(BYTE* data, size_t data_len, uint64_t* msgid, router_header* header) {
	size_t offset = 0;
	size_t len = decode_u64(msgid, data + offset, data_len - offset);
	if (len == 0)
		return 0;
	offset += len;
	len = decode_u64(&header->session_id, data + offset, data_len - offset);
	if (len == 0)
		return 0;
	offset += len;
	len = decode_u64(&header->rpc_flag, data + offset, data_len - offset);
	if (len == 0)
		return 0;
	offset += len;
	len = decode_u64(&header->source_id, data + offset, data_len - offset);
	if (len == 0)
		return 0;
	offset += len;
	return offset;
}

int lua_socket_node::call(lua_State* L) {
	int top = lua_gettop(L);
	if (top < 4) {
		lua_pushinteger(L, -1);
		return 1;
	}
	size_t header_len = format_header(L, header, sizeof(header), rpc_type::remote_call);
	size_t data_len = 0;
	void* data = m_archiver->save(&data_len, L, 4, top);
	if (data == nullptr) {
		lua_pushinteger(L, -2);
		return 1;
	}
	sendv_item items[] = { {header, header_len}, {data, data_len} };
	auto send_len = m_mgr->sendv(m_token, items, _countof(items));
	lua_pushinteger(L, send_len);
	return 1;
}

int lua_socket_node::forward_target(lua_State* L) {
	int top = lua_gettop(L);
	if (top < 5) {
		lua_pushinteger(L, -1);
		return 1;
	}
	size_t header_len = format_header(L, header, sizeof(header), rpc_type::forward_target);
	BYTE svr_id_data[MAX_VARINT_SIZE];
	uint32_t service_id = (uint32_t)lua_tointeger(L, 4);
	size_t svr_id_len = encode_u64(svr_id_data, sizeof(svr_id_data), service_id);
	size_t data_len = 0;
	void* data = m_archiver->save(&data_len, L, 5, top);
	if (data == nullptr) {
		lua_pushinteger(L, -2);
		return 1;
	}
	sendv_item items[] = { {header, header_len}, {svr_id_data, svr_id_len}, {data, data_len} };
	m_mgr->sendv(m_token, items, _countof(items));

	size_t send_len = header_len + svr_id_len + data_len;
	lua_pushinteger(L, send_len);
	return 1;
}

int lua_socket_node::forward_hash(lua_State* L) {
	int top = lua_gettop(L);
	if (top < 6) {
		lua_pushinteger(L, -1);
		return 1;
	}
	size_t header_len = format_header(L, header, sizeof(header), rpc_type::forward_hash);

	uint8_t group_id = (uint8_t)lua_tointeger(L, 4);
	BYTE group_id_data[MAX_VARINT_SIZE];
	size_t group_id_len = encode_u64(group_id_data, sizeof(group_id_data), group_id);

	size_t hash_key = luaL_optinteger(L, 5, 0);

	BYTE hash_data[MAX_VARINT_SIZE];
	size_t hash_len = encode_u64(hash_data, sizeof(hash_data), hash_key);

	size_t data_len = 0;
	void* data = m_archiver->save(&data_len, L, 6, top);
	if (data == nullptr) {
		lua_pushinteger(L, -2);
		return 1;
	}

	sendv_item items[] = { {header, header_len}, {group_id_data, group_id_len}, {hash_data, hash_len}, {data, data_len} };
	m_mgr->sendv(m_token, items, _countof(items));

	size_t send_len = header_len + group_id_len + hash_len + data_len;
	lua_pushinteger(L, send_len);
	return 1;
}

void lua_socket_node::close() {
	if (m_token != 0) {
		m_mgr->close(m_token);
		m_token = 0;
	}
}

void lua_socket_node::on_recv(char* data, size_t data_len) {
	if (eproto_type::proto_pack == m_proto_type) {
		on_call_pack(data, data_len);
		return;
	}
	if (eproto_type::proto_common == m_proto_type) {
		on_call_common(data,data_len);
		return;
	}
	if (eproto_type::proto_text == m_proto_type) {
		on_call_text(data, data_len);
		return;
	}

	uint64_t msg = 0;
	router_header header;
	size_t len = parse_header((BYTE*)data, data_len, &msg, &header);
	if (len == 0)
		return;

	data += len;
	data_len -= len;
	m_error_msg = "";
	bool is_router = false;
	if (msg >= (uint8_t)(rpc_type::forward_router)) {
		msg -= (uint8_t)rpc_type::forward_router;
		is_router = true;
	}
	switch ((rpc_type)msg) {
	case rpc_type::remote_call:
		on_call(&header, data, data_len);
		break;
	case rpc_type::forward_target:
		if (!m_router->do_forward_target(&header, data, data_len, m_error_msg,is_router))
			on_forward_error(&header);
		break;
	case rpc_type::forward_master:
		if (!m_router->do_forward_master(&header, data, data_len, m_error_msg,is_router))
			on_forward_error(&header);
		break;
	case rpc_type::forward_hash:
		if (!m_router->do_forward_hash(&header, data, data_len, m_error_msg,is_router))
			on_forward_error(&header);
		break;
	case rpc_type::forward_broadcast:
		{
		size_t broadcast_num = 0;
		if (m_router->do_forward_broadcast(&header, m_token, data, data_len, broadcast_num))
			on_forward_broadcast(&header, broadcast_num);
		else
			on_forward_error(&header);
		}
		break;
	default:
		break;
	}
}

void lua_socket_node::on_forward_error(router_header* header) {
	if (header->session_id > 0) {//sendµÄÔÝÊ±ºöÂÔ toney
		luakit::kit_state kit_state(m_lvm);
		kit_state.object_call(this, "on_forward_error", nullptr, std::tie(), header->session_id, m_error_msg, header->source_id);
	}
}

void lua_socket_node::on_forward_broadcast(router_header* header, size_t broadcast_num) {
	if (header->session_id > 0) {
		luakit::kit_state kit_state(m_lvm);
		kit_state.object_call(this, "on_forward_broadcast", nullptr, std::tie(), header->session_id, broadcast_num);
	}
}

void lua_socket_node::on_call(router_header* header, char* data, size_t data_len) {
	luakit::lua_guard g(m_lvm);
	if (!luakit::get_object_function(m_lvm, this, "on_call"))
		return;

	lua_pushinteger(m_lvm, data_len);
	lua_pushinteger(m_lvm, header->session_id);
	lua_pushinteger(m_lvm, header->rpc_flag);
	lua_pushinteger(m_lvm, header->source_id);
	int param_count = m_archiver->load(m_lvm, data, data_len);
	if (param_count == 0)
		return;

	luakit::lua_call_function(m_lvm, nullptr, param_count + 4, 0);
}

void lua_socket_node::on_call_pack(char* data, size_t data_len) {
	m_msg_body.clear();
	auto head = (socket_header*)data;
	m_msg_body.append(data + sizeof(socket_header), data_len - sizeof(socket_header));

	luakit::kit_state kit_state(m_lvm);
	kit_state.object_call(this, "on_call_pack",nullptr, std::tie(), data_len, head->cmd_id, head->flag, head->session_id, m_msg_body);
}

void lua_socket_node::on_call_text(char* data, size_t data_len) {
	m_msg_body.clear();
	m_msg_body.append(data, data_len);

	luakit::kit_state kit_state(m_lvm);
	kit_state.object_call(this, "on_call_text",nullptr, std::tie(), data_len, m_msg_body);
}

void lua_socket_node::on_call_common(char* data, size_t data_len) {
	m_msg_body.clear();
	m_msg_body.append(data, data_len);
	luakit::kit_state kit_state(m_lvm);
	kit_state.object_call(this, "on_call_common", nullptr, std::tie(), data_len,m_msg_body);
}

