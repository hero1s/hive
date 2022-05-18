#define LUA_LIB
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#ifdef _MSC_VER
#include <Winsock2.h>
#include <Ws2tcpip.h>
#include <mswsock.h>
#include <windows.h>
#pragma comment(lib, "Ws2_32.lib")
inline int get_socket_error() { return WSAGetLastError(); }
#endif
#if defined(__linux) || defined(__APPLE__)
#include <fcntl.h>
#include <errno.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/udp.h>
typedef struct sockaddr SOCKADDR;
typedef struct sockaddr_in SOCKADDR_IN;
inline void closesocket(int fd) { close(fd); }
inline int get_socket_error() { return errno; }
#endif

#include "ikcp.h"

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"

#define RECV_BUFF_LEN   1024*1024
#define LUA_UDP_META    "_LUA_UDP_META"
#define LUA_KCP_META    "_LUA_KCP_META"
#define LUA_KBUFF_META  "_LUA_KCP_BUFF_META"
#define LUA_UBUFF_META  "_LUA_UDP_BUFF_META"
#define LUA_KCP_RBUFF   "_LUA_KCP_RECV_BUFF"
#define LUA_UDP_RBUFF   "_LUA_UDP_RECV_BUFF"

struct Callback {
    uint64_t handle;
    lua_State* L;
};

static int kcp_output_callback(const char *buf, int len, ikcpcb *kcp, void *arg) {
    struct Callback* c = (struct Callback*)arg;
    lua_State* L = c -> L;
    uint64_t handle = c -> handle;

    lua_rawgeti(L, LUA_REGISTRYINDEX, handle);
    lua_pushlstring(L, buf, len);
    lua_pushinteger(L, kcp->conv);
    lua_call(L, 2, 0);
    return 0;
}

static int kcp_gc(lua_State* L) {
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        return 0;
    }
    if (kcp->user != NULL) {
        struct Callback* c = (struct Callback*)kcp -> user;
        uint64_t handle = c -> handle;
        luaL_unref(L, LUA_REGISTRYINDEX, handle);
        free(c);
        kcp->user = NULL;
    }
    ikcp_release(kcp);
    kcp = NULL;
    return 0;
}

static int lkcp_create(lua_State* L){
    uint64_t handle = luaL_ref(L, LUA_REGISTRYINDEX);
    int32_t conv = luaL_checkinteger(L, 1);

    struct Callback* c = malloc(sizeof(struct Callback));
    memset(c, 0, sizeof(struct Callback));
    c -> handle = handle;
    c -> L = L;

    ikcpcb* kcp = ikcp_create(conv, (void*)c);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: fail to create kcp");
        return 2;
    }

    kcp->output = kcp_output_callback;

    *(ikcpcb**)lua_newuserdata(L, sizeof(void*)) = kcp;
    luaL_getmetatable(L, LUA_KCP_META);
    lua_setmetatable(L, -2);
    return 1;
}

static int lkcp_recv(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    lua_getfield(L, LUA_REGISTRYINDEX, LUA_KCP_RBUFF);
    char* buf = (char*)luaL_checkudata(L, -1, LUA_KBUFF_META);
    lua_pop(L, 1);

    int32_t hr = ikcp_recv(kcp, buf, RECV_BUFF_LEN);
    if (hr <= 0) {
        lua_pushinteger(L, hr);
        return 1;
    }

    lua_pushinteger(L, hr);
    lua_pushlstring(L, (const char *)buf, hr);

    return 2;
}

static int lkcp_send(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    size_t size;
    const char *data = luaL_checklstring(L, 2, &size);
    int32_t hr = ikcp_send(kcp, data, size);
    
    lua_pushinteger(L, hr);
    return 1;
}

static int lkcp_update(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    int32_t current = luaL_checkinteger(L, 2);
    ikcp_update(kcp, current);
    return 0;
}

static int lkcp_check(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    int32_t current = luaL_checkinteger(L, 2);
    int32_t hr = ikcp_check(kcp, current);
    lua_pushinteger(L, hr);
    return 1;
}

static int lkcp_input(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    size_t size;
    const char *data = luaL_checklstring(L, 2, &size);
    int32_t hr = ikcp_input(kcp, data, size);
    
    lua_pushinteger(L, hr);
    return 1;
}

static int lkcp_flush(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    ikcp_flush(kcp);
    return 0;
}

static int lkcp_wndsize(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    int32_t sndwnd = luaL_checkinteger(L, 2);
    int32_t rcvwnd = luaL_checkinteger(L, 3);
    ikcp_wndsize(kcp, sndwnd, rcvwnd);
    return 0;
}

static int lkcp_nodelay(lua_State* L){
    ikcpcb* kcp = *(ikcpcb**)luaL_checkudata(L, 1, LUA_KCP_META);
    if (kcp == NULL) {
        lua_pushnil(L);
        lua_pushstring(L, "error: kcp not args");
        return 2;
    }
    int32_t nodelay = luaL_checkinteger(L, 2);
    int32_t interval = luaL_checkinteger(L, 3);
    int32_t resend = luaL_checkinteger(L, 4);
    int32_t nc = luaL_checkinteger(L, 5);
    int32_t hr = ikcp_nodelay(kcp, nodelay, interval, resend, nc);
    lua_pushinteger(L, hr);
    return 1;
}

static const struct luaL_Reg lkcp_funcs[] = {
    { "recv" , lkcp_recv },
    { "send" , lkcp_send },
    { "update" , lkcp_update },
    { "check" , lkcp_check },
    { "input" , lkcp_input },
    { "flush" , lkcp_flush },
    { "wndsize" , lkcp_wndsize },
    { "nodelay" , lkcp_nodelay },
    {NULL, NULL},
};

typedef struct lua_udp {
    int fd;
} lua_udp_t;

static int udp_listen(lua_State* L) {
    lua_udp_t* udp = (lua_udp_t*)luaL_checkudata(L, 1, LUA_UDP_META);
    if (!udp) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lua_udp is nil!");
        return 2;
    }
    if (lua_gettop(L) < 3) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "param args err!");
        return 2;
    }
    const char* ip = lua_tostring(L, 2);
    int port = lua_tointeger(L, 3);

    SOCKADDR_IN tAddr;
    memset(&tAddr, 0, sizeof(tAddr));
    tAddr.sin_family = AF_INET;
    tAddr.sin_port = htons(port);
    tAddr.sin_addr.s_addr = inet_addr(ip);
    if (bind(udp->fd, (SOCKADDR*)&tAddr, sizeof(tAddr)) < 0) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "socket bind failed!");
        closesocket(udp->fd);
        udp->fd = 0;
        return 2;
    }
    lua_pushboolean(L, true);
    return 1;
}

static int udp_send(lua_State* L) {
    lua_udp_t* udp = (lua_udp_t*)luaL_checkudata(L, 1, LUA_UDP_META);
    if (!udp) {
        lua_pushinteger(L, 0);
        lua_pushstring(L, "lua_udp is nil!");
        return 2;
    }
    if (lua_gettop(L) < 5) {
        lua_pushinteger(L, 0);
        lua_pushstring(L, "param args err!");
        return 2;
    }
    const char* data = lua_tostring(L, 2);
    int len = lua_tointeger(L, 3);
    const char* ip = lua_tostring(L, 4);
    int port = lua_tointeger(L, 5);

    SOCKADDR_IN tAddr;
    memset(&tAddr, 0, sizeof(tAddr));
    tAddr.sin_family = AF_INET;
    tAddr.sin_port = htons(port);
    tAddr.sin_addr.s_addr = inet_addr(ip);
    int send_len = sendto(udp->fd, data, len, 0, (SOCKADDR*)&tAddr, sizeof(tAddr));
    if (send_len <= 0) {
        lua_pushinteger(L, send_len);
        lua_pushstring(L, "send data err!");
        return 2;
    }
    lua_pushinteger(L, send_len);
    return 1;
}

static int udp_recv(lua_State* L) {
    lua_udp_t* udp = (lua_udp_t*)luaL_checkudata(L, 1, LUA_UDP_META);
    if (!udp) {
        lua_pushboolean(L, false);
        lua_pushstring(L, "lua_udp is nil!");
        return 2;
    }

    lua_getfield(L, LUA_REGISTRYINDEX, LUA_UDP_RBUFF);
    char* buf = (char*)luaL_checkudata(L, -1, LUA_UBUFF_META);
    lua_pop(L, 1);

    SOCKADDR_IN tAddr;
    memset(&tAddr, 0, sizeof(tAddr));
    socklen_t nLen = (socklen_t)sizeof(tAddr);
    int recv_len = recvfrom(udp->fd, buf, RECV_BUFF_LEN, 0, (SOCKADDR*)&tAddr, &nLen);
    if (recv_len <= 0) {
        lua_pushboolean(L, false);
        if (get_socket_error() == EWOULDBLOCK) {
            lua_pushstring(L, "EWOULDBLOCK");
            return 2;
        }
        lua_pushstring(L, "recv data err!");
        return 2;
    }
    lua_pushboolean(L, true);
    lua_pushlstring(L, buf, recv_len);
    lua_pushstring(L, inet_ntoa(tAddr.sin_addr));
    lua_pushinteger(L, ntohs(tAddr.sin_port));
    return 4;
}

static int udp_gc(lua_State* L) {
    lua_udp_t* udp = (lua_udp_t*)luaL_checkudata(L, 1, LUA_UDP_META);
    if (!udp) {
        lua_pushinteger(L, false);
        lua_pushstring(L, "lua_udp is nil!");
        return 2;
    }
    if (udp->fd > 0)
        closesocket(udp->fd);
    return 0;
}

static const struct luaL_Reg ludp_funcs[] = {
    {"listen", udp_listen},
    {"send", udp_send},
    {"recv", udp_recv},
    {NULL, NULL}
};

static int ludp_create(lua_State* L) {
    int fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (fd <= 0) {
        lua_pushnil(L);
        lua_pushstring(L, "create socket failed!");
        return 2;
    }
    lua_udp_t* udp = (lua_udp_t*)lua_newuserdata(L, sizeof(lua_udp_t));
    memset(udp, 0, sizeof(lua_udp_t));
#ifdef _MSC_VER
    u_long  opt = 1;
    ioctlsocket(fd, FIONBIO, &opt);
#else
    fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
    fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
#endif
    udp->fd = fd;
    luaL_getmetatable(L, LUA_UDP_META);
    lua_setmetatable(L, -2);
    return 1;
}

static const struct luaL_Reg lkcplib_funcs[] = {
    { "kcp" , lkcp_create },
    { "udp" , ludp_create },
    {NULL, NULL},
};

LUALIB_API int luaopen_lkcp(lua_State* L) {
#ifdef _MSC_VER
    WORD    wVersion = MAKEWORD(2, 2);
    WSADATA wsaData;
    WSAStartup(wVersion, &wsaData);
#endif

    luaL_checkversion(L);
    luaL_newmetatable(L, LUA_KCP_META);
    lua_newtable(L);
    luaL_setfuncs(L, lkcp_funcs, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, kcp_gc);
    lua_setfield(L, -2, "__gc");

    luaL_newmetatable(L, LUA_UDP_META);
    lua_newtable(L);
    luaL_setfuncs(L, ludp_funcs, 0);
    lua_setfield(L, -2, "__index");
    lua_pushcfunction(L, udp_gc);
    lua_setfield(L, -2, "__gc");

    char* kcp_buffer = lua_newuserdata(L, sizeof(char)*RECV_BUFF_LEN);
    memset(kcp_buffer, 0, sizeof(char) * RECV_BUFF_LEN);
    luaL_newmetatable(L, LUA_KBUFF_META);
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, LUA_KCP_RBUFF);

    char* udp_buffer = lua_newuserdata(L, sizeof(char) * RECV_BUFF_LEN);
    memset(udp_buffer, 0, sizeof(char) * RECV_BUFF_LEN);
    luaL_newmetatable(L, LUA_UBUFF_META);
    lua_setmetatable(L, -2);
    lua_setfield(L, LUA_REGISTRYINDEX, LUA_UDP_RBUFF);

    luaL_newlib(L, lkcplib_funcs);
    return 1;
}