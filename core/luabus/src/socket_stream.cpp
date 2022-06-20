#include "stdafx.h"
#include <algorithm>
#include <assert.h>
#include "var_int.h"
#include "socket_mgr.h"
#include "socket_helper.h"
#include "socket_stream.h"

#ifdef _MSC_VER
socket_stream::socket_stream(socket_mgr* mgr, LPFN_CONNECTEX connect_func, eproto_type proto_type) :
    m_proto_type(proto_type) {
    mgr->increase_count();
    m_mgr = mgr;
    m_connect_func = connect_func;
    m_ip[0] = 0;
}
#endif

socket_stream::socket_stream(socket_mgr* mgr, eproto_type proto_type) :
    m_proto_type(proto_type) {
    mgr->increase_count();
    m_proto_type = proto_type;
    m_mgr = mgr;
    m_ip[0] = 0;
}

socket_stream::~socket_stream() {
    if (m_socket != INVALID_SOCKET) {
        closesocket(m_socket);
        m_socket = INVALID_SOCKET;
    }
    if (m_addr != nullptr) {
        freeaddrinfo(m_addr);
        m_addr = nullptr;
    }
    m_mgr->decrease_count();
}

bool socket_stream::get_remote_ip(std::string& ip) {
    ip = m_ip;
    return true;
}

bool socket_stream::accept_socket(socket_t fd, const char ip[]) {
#ifdef _MSC_VER
    if (!wsa_recv_empty(fd, m_recv_ovl))
        return false;
    m_ovl_ref++;
#endif

    memcpy(m_ip, ip, INET6_ADDRSTRLEN);

    m_socket = fd;
    m_link_status = elink_status::link_connected;
    m_last_recv_time = steady_ms();
    return true;
}

void socket_stream::connect(const char node_name[], const char service_name[], int timeout) {
    m_node_name = node_name;
    m_service_name = service_name;
    m_connecting_time = steady_ms() + timeout;
}

void socket_stream::close() {
    if (m_socket == INVALID_SOCKET) {
        m_link_status = elink_status::link_closed;
        return;
    }
    shutdown(m_socket, SD_RECEIVE);
    m_link_status = elink_status::link_colsing;
}

bool socket_stream::update(int64_t now) {
    switch (m_link_status) {
        case elink_status::link_closed: {
#ifdef _MSC_VER
            if (m_ovl_ref != 0) return true;
#endif
            if(m_socket != INVALID_SOCKET) {
                closesocket(m_socket);
                m_socket = INVALID_SOCKET;
            }
            return false;
        }
        case elink_status::link_colsing: {
            if (m_send_buffer.empty()) {
                m_link_status = elink_status::link_closed;
            }
            return true;
        } 
        case elink_status::link_init: {
            if (now > m_connecting_time) {
                on_connect(false, "timeout");
                return true;
            }
            try_connect();
            return true;
        }
        default: {
            if (m_timeout > 0 && now - m_last_recv_time > m_timeout) {
                on_error("timeout");
            }
            dispatch_package();
        }
    }
    return true;
}

#ifdef _MSC_VER
static bool bind_any(socket_t s) {
    struct sockaddr_in6 v6addr;

    memset(&v6addr, 0, sizeof(v6addr));
    v6addr.sin6_family = AF_INET6;
    v6addr.sin6_addr = in6addr_any;
    v6addr.sin6_port = 0;
    auto ret = ::bind(s, (sockaddr*)&v6addr, (int)sizeof(v6addr));
    if (ret != SOCKET_ERROR)
        return true;

    struct sockaddr_in v4addr;
    memset(&v4addr, 0, sizeof(v4addr));
    v4addr.sin_family = AF_INET;
    v4addr.sin_addr.s_addr = INADDR_ANY;
    v4addr.sin_port = 0;

    ret = ::bind(s, (sockaddr*)&v4addr, (int)sizeof(v4addr));
    return ret != SOCKET_ERROR;
}

bool socket_stream::do_connect() {
    if (!bind_any(m_socket)) {
        on_connect(false, "bind-failed");
        return false;
    }

    if (!m_mgr->watch_connecting(m_socket, this)) {
        on_connect(false, "watch-failed");
        return false;
    }

    memset(&m_send_ovl, 0, sizeof(m_send_ovl));
    auto ret = (*m_connect_func)(m_socket, (SOCKADDR*)m_next->ai_addr, (int)m_next->ai_addrlen, nullptr, 0, nullptr, &m_send_ovl);
    if (!ret) {
        m_next = m_next->ai_next;
        int err = get_socket_error();
        if (err == ERROR_IO_PENDING) {
            m_ovl_ref++;
            return true;
        }
        m_link_status = elink_status::link_closed;
        on_connect(false, "connect-failed");
        return false;
    }

    if (!wsa_recv_empty(m_socket, m_recv_ovl)) {
        on_connect(false, "connect-failed");
        return false;
    }

    m_ovl_ref++;
    on_connect(true, "ok");
    return true;
}
#endif

#if defined(__linux) || defined(__APPLE__)
bool socket_stream::do_connect() {
    while (true) {
        auto ret = ::connect(m_socket, m_next->ai_addr, (int)m_next->ai_addrlen);
        if (ret != SOCKET_ERROR) {
            on_connect(true, "ok");
            break;
        }

        int err = get_socket_error();
        if (err == EINTR)
            continue;

        m_next = m_next->ai_next;
        if (err != EINPROGRESS)
            return false;

        if (!m_mgr->watch_connecting(m_socket, this)) {
            on_connect(false, "watch-failed");
            return false;
        }
        break;
    }
    return true;
}
#endif

void socket_stream::try_connect() {
    if (m_addr == nullptr) {
        addrinfo hints;
        struct addrinfo* addr = nullptr;

        memset(&hints, 0, sizeof hints);
        hints.ai_family = AF_UNSPEC; // use AF_INET6 to force IPv6
        hints.ai_socktype = SOCK_STREAM;

        int ret = getaddrinfo(m_node_name.c_str(), m_service_name.c_str(), &hints, &addr);
        if (ret != 0 || addr == nullptr) {
            on_connect(false, "addr-error");
            return;
        }
        m_addr = addr;
        m_next = addr;
    }

    // socket connecting
    if (m_socket != INVALID_SOCKET)
        return;

    while (m_next != nullptr && m_link_status == elink_status::link_init) {
        if (m_next->ai_family != AF_INET && m_next->ai_family != AF_INET6) {
            m_next = m_next->ai_next;
            continue;
        }
        m_socket = socket(m_next->ai_family, m_next->ai_socktype, m_next->ai_protocol);
        if (m_socket == INVALID_SOCKET) {
            m_next = m_next->ai_next;
            continue;
        }
        init_socket_option(m_socket);
        get_ip_string(m_ip, sizeof(m_ip), m_next->ai_addr, m_next->ai_addrlen);

        if (do_connect())
            return;

        if (m_socket != INVALID_SOCKET) {
            closesocket(m_socket);
            m_socket = INVALID_SOCKET;
        }
    }
    on_connect(false, "connect-failed");
}

int socket_stream::send(const void* data, size_t data_len)
{
    int send_len = 0;
    if (m_link_status != elink_status::link_connected)
        return send_len;

    // rpc模式需要发送特殊的head
    if (eproto_type::proto_rpc == m_proto_type){
        BYTE header[MAX_VARINT_SIZE];
        size_t header_len = encode_u64(header, sizeof(header), data_len);
        send_len += stream_send((char*)header, header_len);
    }
    send_len += stream_send((char*)data, data_len);
    return send_len;
}

int socket_stream::sendv(const sendv_item items[], int count)
{
    int send_len = 0;
    if (m_link_status != elink_status::link_connected)
        return send_len;

    size_t data_len = 0;
    for (int i = 0; i < count; i++) {
        data_len += items[i].len;
    }
    // rpc模式需要发送特殊的head
    if (eproto_type::proto_rpc == m_proto_type) {
        BYTE  header[MAX_VARINT_SIZE];
        size_t header_len = encode_u64(header, sizeof(header), data_len);
        send_len += stream_send((char*)header, header_len);
    }
    for (int i = 0; i < count; i++) {
        auto item = items[i];
        send_len += stream_send((char*)item.data, item.len);
    }
    return send_len;
}

int socket_stream::stream_send(const char* data, size_t data_len)
{
    int send_len = data_len;
    if (m_link_status != elink_status::link_connected)
        return 0;
    if (m_send_buffer.data_len() >= IO_BUFFER_SEND)
    {
        do_send(UINT_MAX, false);
    }
    while (data_len > 0) {
        size_t space_len;
        m_send_buffer.peek_space(&space_len);
        if (space_len == 0) {
            on_error("send-buffer-full");
            return 0;
        }
        size_t try_len = std::min<size_t>(space_len, data_len);
        if (!m_send_buffer.push_data(data, try_len)) {
            on_error("send-failed");
            return 0;
        }
        data_len -= try_len;
        data += try_len;
    }
#if _MSC_VER
    if (!wsa_send_empty(m_socket, m_send_ovl)) {
        on_error("send-failed");
        return 0;
    }
    m_ovl_ref++;
#else
    if (!m_mgr->watch_send(m_socket, this, true)) {
        on_error("watch-error");
        return 0;
    }
#endif
    return send_len;
}

#ifdef _MSC_VER
void socket_stream::on_complete(WSAOVERLAPPED* ovl)
{
    m_ovl_ref--;
    if (m_link_status == elink_status::link_closed)
        return;

    if (m_link_status != elink_status::link_init){
        if (ovl == &m_recv_ovl) {
            do_recv(UINT_MAX, false);
        } else {
            do_send(UINT_MAX, false);
        }
        return;
    }

    int seconds = 0;
    socklen_t sock_len = (socklen_t)sizeof(seconds);
    auto ret = getsockopt(m_socket, SOL_SOCKET, SO_CONNECT_TIME, (char*)&seconds, &sock_len);
    if (ret == 0 && seconds != 0xffffffff) {
        if (!wsa_recv_empty(m_socket, m_recv_ovl)) {
            on_connect(false, "connect-failed");
            return;
        }
        m_ovl_ref++;
        on_connect(true, "ok");
        return;
    }

    // socket连接失败,还可以继续dns解析的下一个地址继续尝试
    closesocket(m_socket);
    m_socket = INVALID_SOCKET;
    if (m_next == nullptr) {
        on_connect(false, "connect-failed");
    }
}
#endif

#if defined(__linux) || defined(__APPLE__)
void socket_stream::on_can_send(size_t max_len, bool is_eof) {
    if (m_link_status == elink_status::link_closed)
        return;

    if (m_link_status != elink_status::link_init) {
        do_send(max_len, is_eof);
        return;
    }

    int err = 0;
    socklen_t sock_len = sizeof(err);
    auto ret = getsockopt(m_socket, SOL_SOCKET, SO_ERROR, (char*)&err, &sock_len);
    if (ret == 0 && err == 0 && !is_eof) {
        if (!m_mgr->watch_connected(m_socket, this)) {
            on_connect(false, "watch-error");
            return;
        }
        on_connect(true, "ok");
        return;
    }

    // socket连接失败,还可以继续dns解析的下一个地址继续尝试
    closesocket(m_socket);
    m_socket = INVALID_SOCKET;
    if (m_next == nullptr) {
        on_connect(false, "connect-failed");
    }
}
#endif

void socket_stream::do_send(size_t max_len, bool is_eof) {
    size_t total_send = 0;
    while (total_send < max_len && (m_link_status != elink_status::link_closed)) {
        size_t data_len = 0;
        auto* data = m_send_buffer.peek_data(&data_len);
        if (data_len == 0) {
            if (!m_mgr->watch_send(m_socket, this, false)) {
                on_error("watch-error");
                return;
            }
            break;
        }

        size_t try_len = std::min<size_t>(data_len, max_len - total_send);
        int send_len = ::send(m_socket, (char*)data, (int)try_len, 0);
        if (send_len == SOCKET_ERROR) {
            int err = get_socket_error();
#ifdef _MSC_VER
            if (err == WSAEWOULDBLOCK) {
                if (!wsa_send_empty(m_socket, m_send_ovl)) {
                    on_error("send-failed");
                    return;
                }
                m_ovl_ref++;
                break;
            }
#endif

#if defined(__linux) || defined(__APPLE__)
            if (err == EINTR)
                continue;

            if (err == EAGAIN)
                break;
#endif
            on_error("send-failed");
            return;
        }
        if (send_len == 0) {
            on_error("connection-lost");
            return;
        }
        total_send += send_len;
        m_send_buffer.pop_data((size_t)send_len);
    }
    if (is_eof || max_len == 0) {
        on_error("connection-lost");
    }
}

void socket_stream::do_recv(size_t max_len, bool is_eof)
{
    size_t total_recv = 0;
    while (total_recv < max_len && m_link_status == elink_status::link_connected) {
        size_t space_len = 0;
        auto* space = m_recv_buffer.peek_space(&space_len);
        if (space_len == 0) {
            on_error("recv-buffer-full");
            return;
        }

        size_t try_len = std::min<size_t>(space_len, max_len - total_recv);
        int recv_len = recv(m_socket, (char*)space, (int)try_len, 0);
        if (recv_len < 0) {
            int err = get_socket_error();
#ifdef _MSC_VER
            if (err == WSAEWOULDBLOCK) {
                if (!wsa_recv_empty(m_socket, m_recv_ovl)) {
                    on_error("recv-failed");
                    return;
                }
                m_ovl_ref++;
                break;
            }
#endif
#if defined(__linux) || defined(__APPLE__)
            if (err == EINTR)
                continue;

            if (err == EAGAIN)
                break;
#endif
            on_error("recv-failed");
            return;
        }
        if (recv_len == 0) {
            on_error("connection-lost");
            return;
        }
        total_recv += recv_len;
        m_recv_buffer.pop_space(recv_len);
        m_need_dispatch_pkg = true;
    }

    if (is_eof || max_len == 0) {
        on_error("connection-lost");
    }
}

void socket_stream::dispatch_package() {
    if (!m_need_dispatch_pkg)return;
    m_need_dispatch_pkg = false;

    int64_t now = steady_ms();
    while (m_link_status == elink_status::link_connected) {
        uint64_t package_size = 0;
        size_t data_len = 0, header_len = 0;
        auto* data = m_recv_buffer.peek_data(&data_len);
        if (eproto_type::proto_rpc == m_proto_type) {
            // rpc模式使用decode_u64获取head
            header_len = decode_u64(&package_size, data, data_len);
            if (header_len == 0) break;
        }
        else if (eproto_type::proto_pack == m_proto_type) {
            // pack模式获取socket_header
            header_len = sizeof(socket_header);
            if (data_len < header_len)
                break;
            socket_header* header = (socket_header*)data;
            // 当前包长小于headlen，关闭连接
            if (header->len < header_len) {
                on_error("package-length-err");
                break;
            }
            // 当前包头标识的数据超过最大长度
            if (header->len > NET_PACKET_MAX_LEN) {
                on_error("package-parse-large");
                break;
            }
            package_size = header->len - header_len;
        }
        else if (eproto_type::proto_text == m_proto_type) {
            if (data_len == 0) break;
            package_size = data_len;
        } else {
            on_error("proto-type-not-suppert!");
            break;
        }

        // 数据包还没有收完整
        if (data_len < header_len + package_size) break;
        if (eproto_type::proto_pack == m_proto_type) {
            m_package_cb((char*)data, header_len + (size_t)package_size);
        } else {
            m_package_cb((char*)data + header_len, (size_t)package_size);
        }

        // 接收缓冲读游标调整
        m_recv_buffer.pop_data(header_len + (size_t)package_size);
        m_last_recv_time = steady_ms();

        // 防止单个连接处理太久，不能大于20ms
        if (m_last_recv_time - now > 20) {
            m_need_dispatch_pkg = true;
            break;
        }
    }
}

void socket_stream::on_error(const char err[]) {
    if (m_link_status == elink_status::link_connected) {
        // kqueue实现下,如果eof时不及时关闭或unwatch,则会触发很多次eof
        if (m_socket != INVALID_SOCKET) {
            closesocket(m_socket);
            m_socket = INVALID_SOCKET;
        }
        m_link_status = elink_status::link_closed;
        m_error_cb(err);
    }
}

void socket_stream::on_connect(bool ok, const char reason[]) {
    m_next = nullptr;
    if (m_addr != nullptr) {
        freeaddrinfo(m_addr);
        m_addr = nullptr;
    }
    if (m_link_status == elink_status::link_init) {
        if (!ok) {
            if (m_socket != INVALID_SOCKET) {
                closesocket(m_socket);
                m_socket = INVALID_SOCKET;
            }
            m_link_status = elink_status::link_closed;
        } else {
            m_link_status = elink_status::link_connected;
            m_last_recv_time = steady_ms();
        }
        m_connect_cb(ok, reason);
    }
}
