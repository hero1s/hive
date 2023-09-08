#pragma once

#include <string>
#include <vector>
#include <thread>
#include <mutex>
#include <limits.h>
#include <functional>
#include <unordered_map>
#include "socket_helper.h"

using namespace luakit;

enum class elink_status : uint8_t
{
	link_init = 0,
	link_connected = 1,
	link_colsing = 2,
	link_closed = 3,
};

// 连接类型
enum elink_type : uint8_t
{
	elink_tcp_client = 0, //主动连接
	elink_tcp_accept = 1, //服务连接
};

// 协议类型
enum class eproto_type : int
{
	proto_rpc		= 0,   // rpc协议,根据协议头解析
	proto_head		= 1,   // head协议,根据协议头解析
	proto_text		= 2,   // text协议,文本协议
	proto_wss		= 3,   // wss协议，协议前n个字节带长度
	proto_mongo		= 4,   // mongo协议，协议前4个字节为长度
	proto_mysql		= 5,   // mysql协议，协议前3个字节为长度
	proto_max		= 6,   // max 
};

struct sendv_item
{
	const void* data;
	size_t len;
};

struct socket_object
{
	virtual ~socket_object() {};
	virtual bool update(int64_t now, bool check_timeout) = 0;
	virtual void close() { m_link_status = elink_status::link_closed; };
	virtual bool get_remote_ip(std::string& ip) = 0;
	virtual void connect(const char node_name[], const char service_name[]) { }
	virtual void set_timeout(int duration) { }
	virtual void set_nodelay(int flag) { }
	virtual void set_flow_ctrl(int ctrl_package, int ctrl_bytes){ }
	virtual int  send(const void* data, size_t data_len) { return 0; }
	virtual int  sendv(const sendv_item items[], int count) { return 0; };
	virtual void set_accept_callback(const std::function<void(int, eproto_type)>& cb) { }
	virtual void set_connect_callback(const std::function<void(bool, const char*)>& cb) { }
	virtual void set_package_callback(const std::function<int(slice*)>& cb) { }
	virtual void set_error_callback(const std::function<void(const char*)>& cb) { }

#ifdef _MSC_VER
	virtual void on_complete(WSAOVERLAPPED* ovl) = 0;
#endif

#if defined(__linux) || defined(__APPLE__)
	virtual void on_can_recv(size_t data_len = UINT_MAX, bool is_eof = false) {};
	virtual void on_can_send(size_t data_len = UINT_MAX, bool is_eof = false) {};
#endif
	elink_status link_status() { return m_link_status; };
	void set_handshake(bool status) { m_handshake = status; };
protected:
	eproto_type m_proto_type = eproto_type::proto_rpc;
	elink_status m_link_status = elink_status::link_init;
	bool         m_handshake = true; //握手状态
};

class socket_mgr
{
public:
	socket_mgr();
	~socket_mgr();

	bool setup(uint32_t max_connection);

#ifdef _MSC_VER
	bool get_socket_funcs();
#endif

	int wait(int timeout);

	uint32_t listen(std::string& err, const char ip[], int port, eproto_type proto_type);
	uint32_t connect(std::string& err, const char node_name[], const char service_name[], int timeout, eproto_type proto_type);

	void set_timeout(uint32_t token, int duration);
	void set_nodelay(uint32_t token, int flag);
	void set_flow_ctrl(uint32_t token, int ctrl_package, int ctrl_bytes);
	bool can_send(uint32_t token);
	int  send(uint32_t token, const void* data, size_t data_len);
	int  sendv(uint32_t token, const sendv_item items[], int count);
	void close(uint32_t token);
	bool get_remote_ip(uint32_t token, std::string& ip);

	void set_accept_callback(uint32_t token, const std::function<void(uint32_t, eproto_type eproto_type)>& cb);
	void set_connect_callback(uint32_t token, const std::function<void(bool, const char*)>& cb);
	void set_package_callback(uint32_t token, const std::function<int(slice*)>& cb);
	void set_error_callback(uint32_t token, const std::function<void(const char*)>& cb);

	bool watch_listen(socket_t fd, socket_object* object);
	bool watch_accepted(socket_t fd, socket_object* object);
	bool watch_connecting(socket_t fd, socket_object* object);
	bool watch_connected(socket_t fd, socket_object* object);
	bool watch_send(socket_t fd, socket_object* object, bool enable);
	void unwatch(socket_t fd);
	int accept_stream(socket_t fd, const char ip[], const std::function<void(int, eproto_type)>& cb, eproto_type proto_type = eproto_type::proto_rpc);

	void increase_count() { m_count++; }
	void decrease_count() { m_count--; }
	bool is_full() { return m_count >= m_max_count; }
	socket_object* get_object(int token);
	uint32_t new_token();

	const std::string& get_handshake_verify() { return m_handshake_verify; }
	void set_handshake_verify(const std::string& verify) { m_handshake_verify = verify; }

private:
#ifdef _MSC_VER
	LPFN_ACCEPTEX m_accept_func = nullptr;
	LPFN_CONNECTEX m_connect_func = nullptr;
	LPFN_GETACCEPTEXSOCKADDRS m_addrs_func = nullptr;
	HANDLE m_handle = INVALID_HANDLE_VALUE;
	std::vector<OVERLAPPED_ENTRY> m_events;
#endif

#ifdef __linux
	int m_handle = -1;
	std::vector<epoll_event> m_events;
#endif

#ifdef __APPLE__
	int m_handle = -1;
	std::vector<struct kevent> m_events;
#endif

	int m_max_count = 0;
	int m_count = 0;
	uint32_t m_next_token = 0;
	int64_t  m_last_check_time = 0;
	std::unordered_map<uint32_t, socket_object*> m_objects;
	std::string m_handshake_verify = "CLBY20220816CLBY&*^%$#@!";
};
