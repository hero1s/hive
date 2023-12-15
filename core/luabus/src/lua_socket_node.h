#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "socket_router.h"

struct lua_socket_node final
{
	lua_socket_node(uint32_t token, lua_State* L, stdsptr<socket_mgr>& mgr,
		stdsptr<socket_router> router, bool blisten = false, eproto_type proto_type = eproto_type::proto_rpc);
	~lua_socket_node();

	int call(lua_State* L,uint32_t session_id,uint8_t flag,uint32_t source_id);
	int call_pb(lua_State* L);
	int call_text(lua_State* L);
	int call_data(lua_State* L);

	void close();
	void set_timeout(int ms) { m_mgr->set_timeout(m_token, ms); }
	void set_nodelay(bool flag) { m_mgr->set_nodelay(m_token, flag); }
	void set_codec(codec_base* codec) {
		m_codec = codec;
		m_mgr->set_codec(m_token, codec);
	}
	void set_flow_ctrl(int ctrl_package, int ctrl_bytes) { m_mgr->set_flow_ctrl(m_token, ctrl_package, ctrl_bytes); }
	bool can_send() { return m_mgr->can_send(m_token); }

	int forward_target(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id,uint32_t target);
	int forward_player(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id, uint32_t player_id);
	int forward_hash(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id,uint16_t hash);

	template <rpc_type forward_method>
	int forward_by_group(lua_State* L, uint32_t session_id, uint8_t flag, uint32_t source_id, uint16_t service_id) {
		size_t data_len = 0;
		void* data = m_codec->encode(L, 5, &data_len);
		if (data_len <= SOCKET_PACKET_MAX) {
			router_header header;
			header.session_id = session_id;
			header.rpc_flag = flag;
			header.source_id = source_id;
			header.msg_id = (uint8_t)forward_method;
			header.target_sid = service_id;
			header.len = data_len + sizeof(router_header);
			sendv_item items[] = { {&header, sizeof(router_header)}, {data, data_len} };
			auto send_len = m_mgr->sendv(m_token, items, _countof(items));
			lua_pushinteger(L, send_len);
			return 1;
		}
		lua_pushinteger(L, 0);
		return 1;
	}

public:
	std::string m_ip;
	uint32_t m_token = 0;
private:
	void on_recv(slice* slice);
	void on_call_pb(slice* slice);
	void on_call_data(slice* slice);
	void on_call(router_header* header, slice* slice);
	void on_forward_broadcast(router_header* header, size_t target_size);
	void on_forward_error(router_header* header);

	stdsptr<kit_state> m_luakit;
	stdsptr<socket_mgr> m_mgr;
	codec_base* m_codec = nullptr;
	stdsptr<socket_router> m_router;
	eproto_type m_proto_type;
	std::string m_error_msg;
};

