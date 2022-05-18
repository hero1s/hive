#pragma once
#include <memory>
#include <array>
#include <vector>
#include "socket_mgr.h"
#include "luna.h"
#include "lua_archiver.h"
#include "socket_router.h"

struct lua_socket_mgr final
{
public:
    ~lua_socket_mgr();
    bool setup(lua_State* L, int max_fd);
    int wait(int ms) { return m_mgr->wait(ms); }
    int listen(lua_State* L);
    int connect(lua_State* L);
    void set_package_size(size_t size);
    void set_lz_threshold(size_t size);
    void set_master(uint32_t group_idx, uint32_t token);
    int map_token(lua_State* L);

private:
    lua_State* m_lvm = nullptr;
    std::shared_ptr<socket_mgr> m_mgr;
    std::shared_ptr<lua_archiver> m_archiver;
    std::shared_ptr<socket_router> m_router;

public:
    DECLARE_LUA_CLASS(lua_socket_mgr);
};

