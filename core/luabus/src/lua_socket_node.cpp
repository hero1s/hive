#include "stdafx.h"
#include "fmt/core.h"
#include "lua_socket_node.h"
#include "socket_helper.h"
#include <iostream>

lua_socket_node::lua_socket_node(uint32_t token, lua_State* L, std::shared_ptr<socket_mgr>& mgr,
	std::shared_ptr<socket_router> router, bool blisten, eproto_type proto_type)
	: m_token(token), m_mgr(mgr), m_router(router), m_proto_type(proto_type) {
	m_mgr->get_remote_ip(m_token, m_ip);
	m_luakit = std::make_shared<luakit::kit_state>(L);
	if (blisten) {
		m_mgr->set_accept_callback(token, [=](uint32_t steam_token, eproto_type proto_type) {
			auto stream = new lua_socket_node(steam_token, m_luakit->L(), m_mgr, m_router, false, proto_type);
			stream->set_codec(m_codec);
			m_luakit->object_call(this, "on_accept", nullptr, std::tie(), stream);
			});
	}

	m_mgr->set_connect_callback(token, [=](bool ok, const char* reason) {
		if (ok) {
			m_mgr->get_remote_ip(m_token, m_ip);
		}
		m_luakit->object_call(this, "on_connect", nullptr, std::tie(), ok ? "ok" : reason);
		if (!ok) {
			this->m_token = 0;
		}
		});

	m_mgr->set_error_callback(token, [=](const char* err) {
		auto token = m_token;
		m_token = 0;
		m_luakit->object_call(this, "on_error", nullptr, std::tie(), token, err);
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
	size_t data_len = 0;
	const char* data_ptr = lua_tolstring(L, 4, &data_len);
	if (data_len + sizeof(socket_header) >= NET_PACKET_MAX_LEN) {
		lua_pushinteger(L, -2);
		return 1;
	}
	header.len = data_len + sizeof(socket_header);
	header.seq_id = m_send_seq_id++;

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

int lua_socket_node::call_data(lua_State* L) {
	size_t data_len = 0;
	char* data = (char*)m_codec->encode(L, 1, &data_len);
	if (data_len > SOCKET_PACKET_MAX) return 0;
	m_mgr->send(m_token, data, data_len);
	lua_pushinteger(L, data_len);
	return 1;
}

int lua_socket_node::call(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id) {
	size_t data_len = 0;
	void* data = m_codec->encode(L, 4, &data_len);
	if (data_len <= SOCKET_PACKET_MAX) {
		router_header header;
		header.session_id = session_id;
		header.rpc_flag = flag;
		header.source_id = source_id;
		header.msg_id = (uint8_t)rpc_type::remote_call;
		header.rpc_len = data_len;
		sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
		auto send_len = m_mgr->sendv(m_token, items, _countof(items));
		lua_pushinteger(L, send_len);
		return 1;
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_target(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint32_t target) {
	size_t data_len = 0;
	void* data = m_codec->encode(L, 5, &data_len);
	if (data_len <= SOCKET_PACKET_MAX) {
		router_header header;
		header.session_id = session_id;
		header.rpc_flag = flag;
		header.source_id = source_id;
		header.msg_id = (uint8_t)rpc_type::forward_target;
		header.target_id = target;
		header.rpc_len = data_len;
		sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
		auto send_len = m_mgr->sendv(m_token, items, _countof(items));
		lua_pushinteger(L, send_len);
		return 1;
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_hash(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id, uint16_t hash) {
	size_t data_len = 0;
	void* data = m_codec->encode(L, 6, &data_len);
	if (data_len <= SOCKET_PACKET_MAX) {
		router_header header;
		header.session_id = session_id;
		header.rpc_flag = flag;
		header.source_id = source_id;
		header.msg_id = (uint8_t)rpc_type::forward_hash;
		header.target_id = service_id << 16 | hash;
		header.rpc_len = data_len;
		sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
		auto send_len = m_mgr->sendv(m_token, items, _countof(items));
		lua_pushinteger(L, send_len);
		return 1;
	}
	lua_pushinteger(L, 0);
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
	size_t header_len = sizeof(router_header);
	router_header* header = (router_header*)data;
	data += header_len;
	data_len -= header_len;
	m_error_msg = "";
	bool is_router = false;
	auto msg = header->msg_id;
	if (msg >= (uint8_t)(rpc_type::forward_router)) {
		msg -= (uint8_t)rpc_type::forward_router;
		is_router = true;
	}
	switch ((rpc_type)msg) {
	case rpc_type::remote_call:
		on_call(header, data, data_len);
		break;
	case rpc_type::forward_target:
		if (!m_router->do_forward_target(header, data, data_len, m_error_msg,is_router))
			on_forward_error(header);
		break;
	case rpc_type::forward_master:
		if (!m_router->do_forward_master(header, data, data_len, m_error_msg,is_router))
			on_forward_error(header);
		break;
	case rpc_type::forward_hash:
		if (!m_router->do_forward_hash(header, data, data_len, m_error_msg,is_router))
			on_forward_error(header);
		break;
	case rpc_type::forward_broadcast:
		{
		size_t broadcast_num = 0;
		if (m_router->do_forward_broadcast(header, m_token, data, data_len, broadcast_num))
			on_forward_broadcast(header, broadcast_num);
		else
			on_forward_error(header);
		}
		break;
	default:
		break;
	}
}

void lua_socket_node::on_forward_error(router_header* header) {
	if (header->session_id > 0) {
		m_luakit->object_call(this, "on_forward_error", nullptr, std::tie(), header->session_id, m_error_msg, header->source_id);
	}
}

void lua_socket_node::on_forward_broadcast(router_header* header, size_t broadcast_num) {
	if (header->session_id > 0) {
		m_luakit->object_call(this, "on_forward_broadcast", nullptr, std::tie(), header->session_id, broadcast_num);
	}
}

void lua_socket_node::on_call(router_header* header, char* data, size_t data_len) {
	auto s = slice((uint8_t*)data, data_len);
	m_codec->set_slice(&s);
	m_luakit->object_call(this, "on_call", nullptr, m_codec, std::tie(), data_len, header->session_id, header->rpc_flag, header->source_id);
}

void lua_socket_node::on_call_pack(char* data, size_t data_len) {
	auto head = (socket_header*)data;
	m_luakit->object_call(this, "on_call_pack",nullptr, std::tie(), data_len, head->cmd_id, head->flag, head->session_id, std::string_view(data + sizeof(socket_header), data_len - sizeof(socket_header)));
}

void lua_socket_node::on_call_text(char* data, size_t data_len) {
	m_luakit->object_call(this, "on_call_text",nullptr, std::tie(), data_len, std::string_view(data, data_len));
}

void lua_socket_node::on_call_common(char* data, size_t data_len) {
	m_luakit->object_call(this, "on_call_common", nullptr, std::tie(), data_len, std::string_view(data, data_len));
}

