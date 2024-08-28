#include "stdafx.h"
#include "fmt/core.h"
#include "lua_socket_node.h"
#include "socket_helper.h"
#include <iostream>

lua_socket_node::lua_socket_node(uint32_t token, lua_State* L, stdsptr<socket_mgr>& mgr,
	stdsptr<socket_router> router, bool blisten, eproto_type proto_type)
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

	m_mgr->set_package_callback(token, [=](slice* data) {
		return on_recv(data);
		});
}

lua_socket_node::~lua_socket_node() {
	close();
}

int lua_socket_node::call_pb(lua_State* L) {
	int top = lua_gettop(L);
	if (top < 4) {
		lua_pushinteger(L, -1);
		return 1;
	}
	if (m_codec) {
		size_t data_len = 0;
		char* data = (char*)m_codec->encode(L, 1, &data_len);
		if (data_len > 1 && data_len < NET_PACKET_MAX_LEN) {
			m_mgr->send(m_token, data, data_len);
			lua_pushinteger(L, data_len);
			return 1;
		} else {			
			lua_pushinteger(L, -2);
			return 1;			
		}
	}
	lua_pushinteger(L, -1);
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
	if (m_codec) {
		size_t data_len = 0;
		char* data = (char*)m_codec->encode(L, 1, &data_len);
		if (data_len < SOCKET_PACKET_MAX) {
			m_mgr->send(m_token, data, data_len);
			lua_pushinteger(L, data_len);
			return 1;
		}
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::call(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id) {
	if (m_codec) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 4, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)rpc_type::remote_call;
			header.len = data_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_target(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint32_t target) {
	if (m_codec) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 5, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)rpc_type::forward_target;
			header.target_sid = target;
			header.len = data_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_player(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id, uint32_t player_id) {
	if (m_codec) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 6, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)rpc_type::forward_player;
			header.target_sid = service_id;
			header.target_pid = player_id;
			header.len = data_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_group_player(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id) {
	bus_ids.clear();
	if (!lua_to_native(L, 5, bus_ids) || bus_ids.size() < 1 || bus_ids.size() > 250) {
		lua_pushinteger(L, 0);
		return 1;
	}
	if (m_codec) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 6, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)rpc_type::forward_group_player;
			header.target_sid = service_id;
			header.target_pid = 0;			
			//Íæ¼Òids
			size_t ids_len = 0;
			auto ids_data = m_router->encode_player_ids(bus_ids, &ids_len);
			header.len = data_len + ids_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)},{ids_data, ids_len}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
	}
	lua_pushinteger(L, 0);
	return 1;
}

int lua_socket_node::forward_hash(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id, uint16_t hash) {
	if (m_codec) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 6, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)rpc_type::forward_hash;
			header.target_sid = service_id;
			header.target_pid = hash;
			header.len = data_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
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

int lua_socket_node::on_recv(slice* slice) {
	if (eproto_type::proto_pb == m_proto_type) {
		return on_call_pb(slice);
	}
	if (eproto_type::proto_text == m_proto_type) {
		return on_call_data(slice);
	}
	size_t data_len;
	size_t header_len = sizeof(router_header);
	auto hdata = slice->peek(header_len);
	router_header* header = (router_header*)hdata;

	slice->erase(header_len);
	m_error_msg = "";
	bool is_router = false;
	auto msg = header->msg_id;
	if (msg >= (uint8_t)(rpc_type::forward_router)) {
		msg -= (uint8_t)rpc_type::forward_router;
		is_router = true;
	}
	auto data = (char*)slice->data(&data_len);
	switch ((rpc_type)msg) {
	case rpc_type::remote_call:
		on_call(header, slice);
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
	case rpc_type::forward_player:
		if (!m_router->do_forward_player(header, data, data_len, m_error_msg, is_router))
			on_forward_error(header);
		break;
	case rpc_type::forward_group_player:
		if (!m_router->do_forward_group_player(header, data, data_len, m_error_msg, is_router))
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
	return 0;
}

void lua_socket_node::on_forward_error(router_header* header) {
	if (header->session_id > 0) {
		m_luakit->object_call(this, "on_forward_error", nullptr, std::tie(), header->session_id, m_error_msg, header->source_id, header->msg_id);
	}
}

void lua_socket_node::on_forward_broadcast(router_header* header, size_t broadcast_num) {
	if (header->session_id > 0) {
		m_luakit->object_call(this, "on_forward_broadcast", nullptr, std::tie(), header->session_id, broadcast_num);
	}
}

void lua_socket_node::on_call(router_header* header, slice* slice) {
	m_codec->set_slice(slice);
	m_luakit->object_call(this, "on_call", nullptr, m_codec, std::tie(), slice->size(), header->session_id, header->rpc_flag, header->source_id);
}

int lua_socket_node::on_call_pb(slice* slice) {
	int iRet = 0;
	m_luakit->object_call(this, "on_call_pb", nullptr, m_codec, std::tie(iRet));
	return iRet;
}

int lua_socket_node::on_call_data(slice* slice) {
	if (m_codec) {
		size_t buf_size = slice->size();
		m_luakit->object_call(this, "on_call_data", nullptr, m_codec, std::tie(), buf_size);
	} else {
		m_luakit->object_call(this, "on_call_text", nullptr, std::tie(), slice->size(), slice->contents());
	}
	return 0;
}

