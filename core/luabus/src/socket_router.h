#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "socket_helper.h"

enum class msg_id : char {
    remote_call,
    forward_target,
    forward_master,
    forward_random,
    forward_broadcast,
    forward_hash,
};

const int MAX_SERVICE_GROUP = 255;

struct service_node {
    uint32_t id = 0;
    uint32_t token = 0;
};

struct router_header {
    uint64_t rpc_flag = 0;
    uint64_t source_id = 0;
    uint64_t session_id = 0;
};

struct service_group {
    uint16_t hash = 0;
    uint32_t master = 0;
    std::vector<service_node> nodes;
};

class socket_router
{
public:
    socket_router(std::shared_ptr<socket_mgr>& mgr) : m_mgr(mgr){ }

    void map_token(uint32_t service_id, uint32_t token, uint16_t hash);
    void erase(uint32_t service_id);
    void set_master(uint32_t group_idx, uint32_t token);
    bool do_forward_target(router_header* header, char* data, size_t data_len);
    bool do_forward_master(router_header* header, char* data, size_t data_len);
    bool do_forward_random(router_header* header, char* data, size_t data_len);
    bool do_forward_broadcast(router_header* header, int source, char* data, size_t data_len, size_t& broadcast_num);
    bool do_forward_hash(router_header* header, char* data, size_t data_len);
    size_t format_header(BYTE* header_data, size_t data_len, router_header* header, msg_id msgid);

private:
    std::shared_ptr<socket_mgr> m_mgr;
    std::array<service_group, MAX_SERVICE_GROUP> m_groups;
};

