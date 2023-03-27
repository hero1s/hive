#pragma once
#include<string>

#include "socket_helper.h"

class socket_udp {
public:
    ~socket_udp();

    void close();

    bool setup();

    int listen(lua_State* L, const char* ip, int port);

    int send(lua_State* L, const char* buf, size_t len, const char* ip, int port);

    int recv(lua_State* L);

protected:
    socket_t m_fd;
    char m_recv_buf[SOCKET_RECV_LEN];
};
