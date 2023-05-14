#include "stdafx.h"
#include "socket_dns.h"
#include "socket_udp.h"
#include "socket_tcp.h"
#include "lua_socket_mgr.h"
#include "lua_socket_node.h"

namespace luabus {
	static lua_socket_mgr* create_socket_mgr(lua_State* L, int max_fd) {
		lua_socket_mgr* mgr = new lua_socket_mgr();
		if (!mgr->setup(L, max_fd)) {
			delete mgr;
			return nullptr;
		}
		return mgr;
	}

	static socket_udp* create_udp() {
		socket_udp* udp = new socket_udp();
		if (!udp->setup()) {
			delete udp;
			return nullptr;
		}
		return udp;
	}

	static socket_tcp* create_tcp() {
		socket_tcp* tcp = new socket_tcp();
		if (!tcp->setup()) {
			delete tcp;
			return nullptr;
		}
		return tcp;
	}

    luakit::lua_table open_luabus(lua_State* L) {
        luakit::kit_state kit_state(L);
        auto lluabus = kit_state.new_table();

        lluabus.set_function("udp", create_udp);
        lluabus.set_function("tcp", create_tcp);
        lluabus.set_function("dns", gethostbydomain);
        lluabus.set_function("create_socket_mgr", create_socket_mgr);
        lluabus.set_function("port_is_used", port_is_used);
        lluabus.set_function("lan_ip", get_lan_ip);

        lluabus.new_enum("eproto_type",
            "rpc", eproto_type::proto_rpc,
            "head", eproto_type::proto_pack,
            "text", eproto_type::proto_text,
            "common", eproto_type::proto_common
        );
        kit_state.new_class<socket_udp>(
            "send", &socket_udp::send,
            "recv", &socket_udp::recv,
            "close", &socket_udp::close,
            "listen", &socket_udp::listen
            );
        kit_state.new_class<socket_tcp>(
            "send", &socket_tcp::send,
            "recv", &socket_tcp::recv,
            "close", &socket_tcp::close,
            "accept", &socket_tcp::accept,
            "listen", &socket_tcp::listen,
            "invalid", &socket_tcp::invalid,
            "connect", &socket_tcp::connect
            );
        kit_state.new_class<lua_socket_mgr>(
            "wait", &lua_socket_mgr::wait,
            "listen", &lua_socket_mgr::listen,
            "connect", &lua_socket_mgr::connect,
            "map_token", &lua_socket_mgr::map_token,
            "set_node_status",&lua_socket_mgr::set_node_status,
            "map_router_node",&lua_socket_mgr::map_router_node,
            "set_router_id",&lua_socket_mgr::set_router_id,
            "set_rpc_key",&lua_socket_mgr::set_rpc_key,
            "get_rpc_key",&lua_socket_mgr::get_rpc_key
            );
        kit_state.new_class<lua_socket_node>(
            "ip", &lua_socket_node::m_ip,
            "token", &lua_socket_node::m_token,
            "call", &lua_socket_node::call,
            "call_pack",&lua_socket_node::call_pack,
            "call_text",&lua_socket_node::call_text,
            "call_slice", &lua_socket_node::call_slice,
            "forward_hash", &lua_socket_node::forward_hash,
            "forward_target", &lua_socket_node::forward_target,
            "forward_master", &lua_socket_node::forward_by_group<rpc_type::forward_master>,
            "forward_broadcast", &lua_socket_node::forward_by_group < rpc_type::forward_broadcast>,
            "close", &lua_socket_node::close,
            "set_send_buffer_size",&lua_socket_node::set_send_buffer_size,
            "set_recv_buffer_size",&lua_socket_node::set_recv_buffer_size,
            "set_nodelay", &lua_socket_node::set_nodelay,
            "set_timeout", &lua_socket_node::set_timeout,
            "set_flow_ctrl",&lua_socket_node::set_flow_ctrl,
            "can_send",&lua_socket_node::can_send
            );
        return lluabus;
    }
}

extern "C" {
	LUALIB_API int luaopen_luabus(lua_State* L) {
		auto lluabus = luabus::open_luabus(L);
		return lluabus.push_stack();
	}
}
