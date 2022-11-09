#pragma once
#include<string>
#include "luna.h"
#include "socket_helper.h"

class socket_tcp final 
{
public:
    socket_tcp() {}
    socket_tcp(uint64_t fd) : m_fd(fd) {};

    ~socket_tcp();
    
    void close();

    bool setup();

    bool invalid();

    int accept(lua_State* L);

    int listen(lua_State* L);

    int connect(lua_State* L);

    int send(lua_State* L);

    int recv(lua_State* L);

protected:
    int socket_waitfd(socket_t fd, int sw, size_t tm);

protected:
    socket_t m_fd;
    char m_recv_buf[SOCKET_RECV_LEN];
public:
    DECLARE_LUA_CLASS(socket_tcp);
};
