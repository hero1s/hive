#pragma once
#include <thread>
#include <chrono>

using namespace std::chrono;

constexpr int NET_PACKET_MAX_LEN = (64 * 1024 - 1);

struct socket_header {
    uint16_t    len;            // 整个包的长度
    uint8_t     flag;           // 标志位
    uint8_t     seq_id;         // cli->svr 客户端请求序列号，递增，可用于防止包回放; svr->cli 服务端发给客户端的包序列号，客户端收到的包序号不连续，则主动断开
    uint32_t    cmd_id;         // 协议ID
    uint32_t    session_id;     // sessionId
};

#if defined(__linux) || defined(__APPLE__)
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <cstring>
#include <sys/stat.h>
using socket_t = int;
using BYTE = unsigned char;
const socket_t INVALID_SOCKET = -1;
const int SOCKET_ERROR = -1;
inline int get_socket_error() { return errno; }
inline void closesocket(socket_t fd) { close(fd); }
template <typename T, int N>
constexpr int _countof(T(&_array)[N]) { return N; }
#define SD_RECEIVE SHUT_RD
#endif

#ifdef _MSC_VER
using socket_t = SOCKET;
inline int get_socket_error() { return WSAGetLastError(); }
bool wsa_send_empty(socket_t fd, WSAOVERLAPPED& ovl);
bool wsa_recv_empty(socket_t fd, WSAOVERLAPPED& ovl);
#endif

bool make_ip_addr(sockaddr_storage* addr, size_t* len, const char ip[], int port);
// ip字符串建议大小: char ip[INET6_ADDRSTRLEN];
bool get_ip_string(char ip[], size_t ip_size, const void* addr, size_t addr_len);

// timeout: 单位ms,传入-1表示阻塞到永远
bool check_can_write(socket_t fd, int timeout);

void set_no_block(socket_t fd);
void set_no_delay(socket_t fd, int enable);
void set_close_on_exec(socket_t fd);
void set_keepalive(socket_t fd,int enable);

#define MAX_ERROR_TXT 128

char* get_error_string(char buffer[], int len, int no);
void get_error_string(std::string& err, int no);

inline uint64_t steady_ms() {
	steady_clock::duration dur = steady_clock::now().time_since_epoch();
	return duration_cast<milliseconds>(dur).count();
}

void init_socket_option(socket_t fd);