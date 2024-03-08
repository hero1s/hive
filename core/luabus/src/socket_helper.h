#pragma once
#include <thread>
#include <chrono>
#include <string>
#include <vector>

using namespace std::chrono;

constexpr int NET_PACKET_MAX_LEN	= (64 * 1024 - 1);
constexpr int SOCKET_RECV_LEN		= 16*1024;
constexpr int IO_BUFFER_SEND		= 8*1024;
constexpr int SOCKET_PACKET_MAX		= 1024 * 1024 * 16; //16m

#if defined(__linux) || defined(__APPLE__)
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <cstring>
#include <sys/stat.h>
#include <netinet/udp.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_arp.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/sysinfo.h>
#include <sys/resource.h>
#include <sys/ioctl.h>
#include <sys/time.h>

using socket_t = int;
using BYTE = unsigned char;
const socket_t INVALID_SOCKET = -1;
const int SOCKET_ERROR = -1;
inline int get_socket_error() { return errno; }
inline void closesocket(socket_t fd) { close(fd); }
template <typename T, int N>
constexpr int _countof(T(&_array)[N]) { return N; }
#define SD_RECEIVE SHUT_RD
#define WSAEWOULDBLOCK EWOULDBLOCK
#define WSAEINPROGRESS EINPROGRESS
#endif

#ifdef _MSC_VER
using socket_t = SOCKET;
inline int get_socket_error() { return WSAGetLastError(); }
bool wsa_send_empty(socket_t fd, WSAOVERLAPPED& ovl);
bool wsa_recv_empty(socket_t fd, WSAOVERLAPPED& ovl);
#endif

template <typename T>
using stdsptr = std::shared_ptr<T>;

bool make_ip_addr(sockaddr_storage* addr, size_t* len, const char ip[], int port);
// ip字符串建议大小: char ip[INET6_ADDRSTRLEN];
bool get_ip_string(char ip[], size_t ip_size, const void* addr, size_t addr_len);

// timeout: 单位ms,传入-1表示阻塞到永远
bool check_can_write(socket_t fd, int timeout);
bool port_is_used(int port,int is_tcp);

void set_no_block(socket_t fd);
void set_no_delay(socket_t fd, int enable);
void set_close_on_exec(socket_t fd);
void set_keepalive(socket_t fd, int enable);
void set_reuseaddr(socket_t fd);

#define MAX_ERROR_TXT 128

char* get_error_string(char buffer[], int len, int no);
void get_error_string(std::string& err, int no);

inline uint64_t steady_ms() {
	return duration_cast<milliseconds>(steady_clock::now().time_since_epoch()).count();
}

void init_socket_option(socket_t fd);

