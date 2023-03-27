#pragma once
#include<string>

#include "socket_helper.h"

class socket_tcp {
public:
    socket_tcp() {}
    socket_tcp(socket_t fd) : m_fd(fd) {};

    ~socket_tcp();

    void close();

    bool setup();

    bool invalid();

    int accept(lua_State* L, int timeout);

    int listen(lua_State* L, const char* ip, int port);

    int connect(lua_State* L, const char* ip, int port, int timeout);

    int send(lua_State* L, const char* buf, size_t len, int timeout);

    int recv(lua_State* L, int timeout);

protected:
    int socket_waitfd(socket_t fd, int sw, size_t tm);

protected:
    socket_t m_fd;
    char m_recv_buf[SOCKET_RECV_LEN];
};
