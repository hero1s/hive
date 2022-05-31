--socket.lua
local ssub          = string.sub
local sfind         = string.find
local log_err       = logger.err
local log_info      = logger.info
local hxpcall       = hive.xpcall

local socket_mgr        = hive.get("socket_mgr")
local thread_mgr        = hive.get("thread_mgr")

local CONNECT_TIMEOUT   = hive.enum("NetwkTime", "CONNECT_TIMEOUT")
local NETWORK_TIMEOUT   = hive.enum("NetwkTime", "NETWORK_TIMEOUT")

local Socket = class()
local prop = property(Socket)
prop:reader("ip", nil)
prop:reader("host", nil)
prop:reader("token", nil)
prop:reader("alive", false)
prop:reader("alive_time", 0)
prop:reader("session", nil)          --连接成功对象
prop:reader("listener", nil)
prop:reader("recvbuf", "")
prop:reader("port", 0)

function Socket:__init(host)
    self.host = host
end

function Socket:__release()
    self:close()
end

function Socket:close()
    if self.session then
        self.session.close()
        self.alive = false
        self.session = nil
        self.token = nil
    end
end

function Socket:listen(ip, port)
    if self.listener then
        return true
    end
    local proto_type = 2
    self.listener = socket_mgr.listen(ip, port, proto_type)
    if not self.listener then
        log_err("[Socket][listen] failed to listen: %s:%d type=%d", ip, port, proto_type)
        return false
    end
    self.ip, self.port = ip, port
    log_info("[Socket][listen] start listen at: %s:%d type=%d", ip, port, proto_type)
    self.listener.on_accept = function(session)
        hxpcall(self.on_socket_accept, "on_socket_accept: %s", self, session, ip, port)
    end
    return true
end

function Socket:connect(ip, port)
    if self.session then
        return true
    end
    local proto_type = 2
    local session, cerr = socket_mgr.connect(ip, port, CONNECT_TIMEOUT, proto_type)
    if not session then
        log_err("[Socket][connect] failed to connect: %s:%d type=%d, err=%s", ip, port, proto_type, cerr)
        return false, cerr
    end
    --设置阻塞id
    local block_id = thread_mgr:build_session_id()
    session.on_connect = function(res)
        local success = res == "ok"
        if not success then
            self:on_socket_error(session.token, res)
        end
        self.alive = success
        self.alive_time = hive.clock_ms
        thread_mgr:response(block_id, success, res)
    end
    session.on_call_text = function(recv_len, data)
        hxpcall(self.on_socket_recv, "on_socket_recv: %s", self, session, data)
    end
    session.on_error = function(token, err)
        thread_mgr:fork(function()
            self:on_socket_error(token, err)
        end)
    end
    self.session = session
    self.token = session.token
    self.ip, self.port = ip, port
    --阻塞模式挂起
    return thread_mgr:yield(block_id, "connect", CONNECT_TIMEOUT)
end

function Socket:on_socket_accept(session)
    local socket = Socket(self.host)
    socket:accept(session, session.ip, self.port)
end

function Socket:on_socket_recv(session, data)
    self.recvbuf = self.recvbuf .. data
    self.alive_time = hive.clock_ms
    self.host:on_socket_recv(self, self.token)
end

function Socket:on_socket_error(token, err)
    if self.session then
        self.session = nil
        self.alive = false
        log_info("[Socket][on_socket_error] err: %s - %s!", err, token)
        self.host:on_socket_error(self, token, err)
        self.token = nil
    end
end

function Socket:accept(session, ip, port)
    session.set_timeout(NETWORK_TIMEOUT)
    session.on_call_text = function(recv_len, data)
        hxpcall(self.on_socket_recv, "on_socket_recv: %s", self, session, data)
    end
    session.on_error = function(token, err)
        thread_mgr:fork(function()
            self:on_socket_error(token, err)
        end)
    end
    self.alive = true
    self.session = session
    self.token = session.token
    self.ip, self.port = ip, port
    self.host:on_socket_accept(self, self.token)
end

function Socket:peek(len, offset)
    offset = offset or 0
    if offset + len <= #self.recvbuf then
        return ssub(self.recvbuf, offset + 1, offset + len)
    end
end

function Socket:peek_data(split_char, offset)
    offset = offset or 0
    local i, j = sfind(self.recvbuf, split_char, offset + 1)
    if i then
        return ssub(self.recvbuf, offset + 1, i - 1), j - offset
    end
end

function Socket:pop(len)
    if len > 0 then
        if #self.recvbuf > len then
            self.recvbuf = ssub(self.recvbuf, len + 1)
        else
            self.recvbuf = ""
        end
    end
end

function Socket:send(data)
    if self.alive and data then
        local send_len = self.session.call_text(data)
        return send_len > 0
    end
    log_err("[Socket][send] the socket not alive, can't send")
    return false
end

return Socket
