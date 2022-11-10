#pragma once
#include "luna.h"

#ifndef WIN32
#include <netdb.h>
#endif

inline int gethostbydomain(lua_State* L) {
    const char* domain = lua_tostring(L, 1);
    if (domain == nullptr) {
        lua_pushnil(L);
        return 1;
    }
 #ifdef WIN32
    struct hostent* host = gethostbyname(domain);
    if (host && host->h_addrtype == AF_INET && *(host->h_addr_list) != nullptr) {
        struct in_addr addr;
        addr.s_addr = *(u_long*)(*(host->h_addr_list));
        char* ipAddr = inet_ntoa(addr);
        lua_pushstring(L, ipAddr);
        return 1;
    }
#else
    struct addrinfo hints;
    memset(&hints, 0, sizeof(struct addrinfo));
    hints.ai_family = AF_UNSPEC;
    hints.ai_flags = AI_CANONNAME;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = 0;  /* any protocol */
    struct addrinfo* result, * result_pointer;
    if (getaddrinfo(domain, NULL, &hints, &result) == 0) {
        for (result_pointer = result; result_pointer != NULL; result_pointer = result_pointer->ai_next) {
            if (AF_INET == result_pointer->ai_family) {
                char ipAddr[32] = {0};
                if (getnameinfo(result_pointer->ai_addr, result_pointer->ai_addrlen, ipAddr, sizeof(ipAddr), nullptr, 0, NI_NUMERICHOST) == 0) {
                    lua_pushstring(L, ipAddr);
                    freeaddrinfo(result);
                    return 1;
                }
            }
        }
        freeaddrinfo(result);
    }
 #endif
    lua_pushnil(L);
    return 1;
}