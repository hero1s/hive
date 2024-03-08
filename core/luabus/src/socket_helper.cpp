#include "stdafx.h"
#include "socket_helper.h"
#include <chrono>
#include <algorithm>

using namespace std::chrono;

void set_no_delay(socket_t fd, int enable) {
#ifdef _MSC_VER
	setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, (const char*)&enable, sizeof(enable));
#else
	setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &enable, sizeof(enable));
#endif
}

void set_keepalive(socket_t fd, int enable) {
	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, (const char*)&enable, sizeof(enable));
}

void set_reuseaddr(socket_t fd) {
	int one = 1;
#ifdef _MSC_VER
	//setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, (const char*)&one, sizeof(one)); win不开启
#else
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
#endif
}

#if defined(__linux) || defined(__APPLE__)
void set_no_block(socket_t fd) {
	fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK);
}

void set_close_on_exec(socket_t fd) {
	fcntl(fd, F_SETFD, fcntl(fd, F_GETFD) | FD_CLOEXEC);
}
#endif

#ifdef _MSC_VER
void set_no_block(socket_t fd) {
	u_long  opt = 1;
	ioctlsocket(fd, FIONBIO, &opt);
}

void set_close_on_exec(socket_t fd) {
    SetHandleInformation ((HANDLE)fd, HANDLE_FLAG_INHERIT, 0);
}

static char s_zero = 0;
bool wsa_send_empty(socket_t fd, WSAOVERLAPPED& ovl) {
	DWORD bytes = 0;
	WSABUF ws_buf = { 0, &s_zero };

	memset(&ovl, 0, sizeof(ovl));
	int ret = WSASend(fd, &ws_buf, 1, &bytes, 0, &ovl, nullptr);
	if (ret == 0) {
		return true;
	}
	else if (ret == SOCKET_ERROR) {
		int err = get_socket_error();
		if (err == WSA_IO_PENDING) {
			return true;
		}
	}
	return false;
}

bool wsa_recv_empty(socket_t fd, WSAOVERLAPPED& ovl) {
	DWORD bytes = 0;
	DWORD flags = 0;
	WSABUF ws_buf = { 0, &s_zero };

	memset(&ovl, 0, sizeof(ovl));
	int ret = WSARecv(fd, &ws_buf, 1, &bytes, &flags, &ovl, nullptr);
	if (ret == 0) {
		return true;
	}
	else if (ret == SOCKET_ERROR) {
		int err = get_socket_error();
		if (err == WSA_IO_PENDING) {
			return true;
		}
	}
	return false;
}
#endif

bool make_ip_addr(sockaddr_storage* addr, size_t* len, const char ip[], int port) {
	if (strchr(ip, ':')) {
		sockaddr_in6* ipv6 = (sockaddr_in6*)addr;
		memset(ipv6, 0, sizeof(*ipv6));
		ipv6->sin6_family = AF_INET6;
		ipv6->sin6_port = htons(port);
		ipv6->sin6_addr = in6addr_any;
		*len = sizeof(*ipv6);
		return ip[0] == '\0' || inet_pton(AF_INET6, ip, &ipv6->sin6_addr) == 1;
	}

	sockaddr_in* ipv4 = (sockaddr_in*)addr;
	memset(ipv4, 0, sizeof(*ipv4));
	ipv4->sin_family = AF_INET;
	ipv4->sin_port = htons(port);
	ipv4->sin_addr.s_addr = INADDR_ANY;
	*len = sizeof(*ipv4);
	return ip[0] == '\0' || inet_pton(AF_INET, ip, &ipv4->sin_addr) == 1;
}

bool get_ip_string(char ip[], size_t ip_size, const void* addr, size_t addr_len) {
	auto* saddr = (sockaddr*)addr;

	ip[0] = '\0';

	if (addr_len >= sizeof(sockaddr_in) && saddr->sa_family == AF_INET) {
		auto* ipv4 = (sockaddr_in*)addr;
		return inet_ntop(ipv4->sin_family, &ipv4->sin_addr, ip, ip_size) != nullptr;
	}
	else if (addr_len >= sizeof(sockaddr_in6) && saddr->sa_family == AF_INET6) {
		auto* ipv6 = (sockaddr_in6*)addr;
		return inet_ntop(ipv6->sin6_family, &ipv6->sin6_addr, ip, ip_size) != nullptr;
	}
	return false;
}

bool check_can_write(socket_t fd, int timeout) {
	timeval tv = { timeout / 1000, 1000 * (timeout % 1000) };
	fd_set wset;

	FD_ZERO(&wset);
	FD_SET(fd, &wset);

	return select((int)fd + 1, nullptr, &wset, nullptr, timeout >= 0 ? &tv : nullptr) == 1;
}

bool port_is_used(int port, int is_tcp) {
	int fd = INVALID_SOCKET;
	if (is_tcp == 1) {
		fd = socket(AF_INET, SOCK_STREAM, IPPROTO_IP);
	}
	else {
		fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	}
	size_t addr_len = 0;
	sockaddr_storage addr;
	make_ip_addr(&addr, &addr_len, "0.0.0.0", port);
	if (::bind(fd, (sockaddr*)&addr, (int)addr_len) == SOCKET_ERROR) {
		closesocket(fd);
		return true;
	}
	closesocket(fd);
	return false;
}

char* get_error_string(char buffer[], int len, int no) {
	buffer[0] = '\0';

#ifdef _WIN32
	FormatMessageA(FORMAT_MESSAGE_FROM_SYSTEM, nullptr, no, 0, buffer, len, nullptr);
#endif

#if defined(__linux) || defined(__APPLE__)
	strerror_r(no, buffer, len);
#endif

	return buffer;
}

void get_error_string(std::string& err, int no) {
	char txt[MAX_ERROR_TXT];
	get_error_string(txt, sizeof(txt), no);
	err = txt;
}

void init_socket_option(socket_t fd) {
	set_no_block(fd);
	set_no_delay(fd, 1);
	set_close_on_exec(fd);
}

