#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "luna.h"
#include "lua_archiver.h"
#include "socket_router.h"

struct lua_socket_node final
{
    lua_socket_node(uint32_t token, lua_State* L, std::shared_ptr<socket_mgr>& mgr, 
    	std::shared_ptr<lua_archiver>& ar, std::shared_ptr<socket_router> router, bool blisten = false, eproto_type proto_type = eproto_type::proto_rpc);
    ~lua_socket_node();

    int call(lua_State* L);
    int call_pack(lua_State* L);
    int call_text(lua_State* L);
    int forward_target(lua_State* L);

    template <msg_id forward_method>
    int forward_by_group(lua_State* L);

    int forward_hash(lua_State* L);

    void close();
    void set_send_buffer_size(size_t size) { m_mgr->set_send_buffer_size(m_token, size); }
    void set_recv_buffer_size(size_t size) { m_mgr->set_recv_buffer_size(m_token, size); }
    void set_timeout(int ms) { m_mgr->set_timeout(m_token, ms); }
    void set_nodelay(bool flag) { m_mgr->set_nodelay(m_token, flag); }
    bool can_send() { return m_mgr->can_send(m_token); }
private:
	void on_recv(char* data, size_t data_len);
    void on_call_pack(char* data, size_t data_len);
    void on_call_text(char* data, size_t data_len);
    void on_call(router_header* header, char* data, size_t data_len);
    void on_forward_broadcast(router_header* header, size_t target_size);
    void on_forward_error(router_header* header);
    size_t format_header(lua_State* L, BYTE* header_data, size_t data_len, msg_id msgid);
    size_t parse_header(BYTE* data, size_t data_len, uint64_t* msgid, router_header* header);

    uint32_t m_token = 0;
    lua_State* m_lvm = nullptr;
    std::string m_ip;
    std::shared_ptr<socket_mgr> m_mgr;
    std::shared_ptr<lua_archiver> m_archiver;
    std::shared_ptr<socket_router> m_router;
    eproto_type m_proto_type;  
    std::string m_msg_body;
    std::string m_error_msg;
    uint8_t m_seq_id = 0;
public:
    DECLARE_LUA_CLASS(lua_socket_node);
};

