#pragma once
#include "socket_helper.h"

#ifndef WIN32
#include <netdb.h>
#endif

inline int gethostip(lua_State* L) {
    int sock_fd = socket(AF_INET, SOCK_DGRAM, 0);
    struct sockaddr_in remote_addr;
    struct sockaddr_in local_addr;
    remote_addr.sin_family = AF_INET;
    remote_addr.sin_port = htons(53);
    remote_addr.sin_addr.s_addr = inet_addr("1.1.1.1");
    if (connect(sock_fd, (struct sockaddr*)&remote_addr, sizeof(struct sockaddr_in)) != 0) {
        closesocket(sock_fd);
        return 0;
    }
    socklen_t len = sizeof(struct sockaddr_in);
    getsockname(sock_fd, (struct sockaddr*)&local_addr, &len);
    char* local_ip = inet_ntoa(local_addr.sin_addr);
    closesocket(sock_fd);
    if (local_ip) {
        lua_pushstring(L, local_ip);
        return 1;
    }
    return 0;
}

inline int gethostbydomain(lua_State* L, std::string domain) {
    struct addrinfo hints;
    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = AI_CANONNAME;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = 0;  /* any protocol */
    struct addrinfo* result, * result_pointer;
    if (getaddrinfo(domain.c_str(), NULL, &hints, &result) == 0) {
        std::vector<std::string> addrs;
        for (result_pointer = result; result_pointer != NULL; result_pointer = result_pointer->ai_next) {
            if (AF_INET == result_pointer->ai_family) {
                char ipaddr[32] = { 0 };
                if (getnameinfo(result_pointer->ai_addr, result_pointer->ai_addrlen, ipaddr, sizeof(ipaddr), nullptr, 0, NI_NUMERICHOST) == 0) {
                    addrs.push_back(ipaddr);
                }
            }
        }
        freeaddrinfo(result);
        return luakit::variadic_return(L, addrs);
    }
    lua_pushnil(L);
    return 1;
}