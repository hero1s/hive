#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "socket_router.h"

struct lua_socket_node final
{
	lua_socket_node(uint32_t token, lua_State* L, std::shared_ptr<socket_mgr>& mgr,
		codec_base* codec, std::shared_ptr<socket_router> router, bool blisten = false, eproto_type proto_type = eproto_type::proto_rpc);
	~lua_socket_node();

	int call(lua_State* L);
	int call_pack(lua_State* L);
	int call_text(lua_State* L);

	void close();
	void set_send_buffer_size(size_t size) { m_mgr->set_send_buffer_size(m_token, size); }
	void set_recv_buffer_size(size_t size) { m_mgr->set_recv_buffer_size(m_token, size); }
	void set_timeout(int ms) { m_mgr->set_timeout(m_token, ms); }
	void set_nodelay(bool flag) { m_mgr->set_nodelay(m_token, flag); }
	void set_flow_ctrl(int ctrl_package, int ctrl_bytes) { m_mgr->set_flow_ctrl(m_token, ctrl_package, ctrl_bytes); }
	bool can_send() { return m_mgr->can_send(m_token); }

	int forward_target(lua_State* L);
	int forward_hash(lua_State* L);

	template <rpc_type forward_method>
	int forward_by_group(lua_State* L) {
		int top = lua_gettop(L);
		if (top < 5) {
			lua_pushinteger(L, -1);
			return 1;
		}
		router_header header;
		size_t header_len = format_header(L, &header, forward_method);
		header.target_id = (uint16_t)lua_tointeger(L, 4);

		size_t data_len = 0;
		void* data = m_codec->encode(L, 5, &data_len);
		if (data == nullptr) {
			lua_pushinteger(L, -2);
			return 1;
		}
		header.rpc_len = data_len;
		sendv_item items[] = { {&header, header_len}, {data, data_len} };
		m_mgr->sendv(m_token, items, _countof(items));

		size_t send_len = header_len + data_len;
		lua_pushinteger(L, data_len);
		return 1;
	}

public:
	std::string m_ip;
	uint32_t m_token = 0;
private:
	void on_recv(char* data, size_t data_len);
	void on_call_pack(char* data, size_t data_len);
	void on_call_text(char* data, size_t data_len);
	void on_call_common(char* data, size_t data_len);
	void on_call(router_header* header, char* data, size_t data_len);
	void on_forward_broadcast(router_header* header, size_t target_size);
	void on_forward_error(router_header* header);
	size_t format_header(lua_State* L, router_header* header, rpc_type msgid);

	std::shared_ptr<kit_state> m_luakit;
	std::shared_ptr<socket_mgr> m_mgr;
	codec_base* m_codec = nullptr;
	std::shared_ptr<socket_router> m_router;
	eproto_type m_proto_type;
	std::string m_error_msg;
	uint8_t m_send_seq_id = 0;
};

