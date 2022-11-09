#pragma once
#include<string>
#include "luna.h"
#include "socket_helper.h"

class socket_udp final 
{
public:
    socket_udp() {};
    ~socket_udp();
    
    void close();

    bool setup();

    int listen(lua_State* L);

    int send(lua_State* L);

    int recv(lua_State* L);

protected:
    socket_t m_fd;
    char m_recv_buf[SOCKET_RECV_LEN];
public:
    DECLARE_LUA_CLASS(socket_udp);
};
