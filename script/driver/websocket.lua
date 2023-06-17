--websocket.lua
local lhttp             = require("lhttp")
local lcrypt            = require("lcrypt")
local lbus              = require("luabus")

local ssub              = string.sub
local spack             = string.pack
local sformat           = string.format
local sunpack           = string.unpack
local log_err           = logger.err
local log_info          = logger.info
local lsha1             = lcrypt.sha1
local lxor_byte         = lcrypt.xor_byte
local lb64encode        = lcrypt.b64_encode

local hxpcall           = hive.xpcall

local thread_mgr        = hive.get("thread_mgr")

local NETWORK_TIMEOUT   = hive.enum("NetwkTime", "NETWORK_TIMEOUT")
local HTTP_CALL_TIMEOUT = hive.enum("NetwkTime", "HTTP_CALL_TIMEOUT")

local WebSocket         = class()
local prop              = property(WebSocket)
prop:reader("ip", nil)
prop:reader("host", nil)
prop:reader("token", nil)
prop:reader("alive", false)
prop:reader("alive_time", 0)
prop:reader("proto_type", 2)
prop:reader("session", nil)         --连接成功对象
prop:reader("listener", nil)
prop:reader("recvbuf", "")
prop:reader("context", nil)         --context
prop:reader("url", "")
prop:reader("port", 0)
prop:accessor("timeout", NETWORK_TIMEOUT)

function WebSocket:__init(host)
    self.host = host
end

function WebSocket:close()
    if self.session then
        if self.alive then
            self:send_frame(true, 0x8, "")
        end
        self.session.close()
        self.context = nil
        self.alive   = false
        self.session = nil
        self.token   = nil
    end
end

function WebSocket:listen(ip, port)
    if self.listener then
        return true
    end
    self.listener = lbus.listen(ip, port, self.proto_type)
    if not self.listener then
        log_err("[WebSocket][listen] failed to listen: %s:%d type=%d", ip, port, self.proto_type)
        return false
    end
    self.ip, self.port = ip, port
    log_info("[WebSocket][listen] start listen at: %s:%d type=%d", ip, port, self.proto_type)
    self.listener.on_accept = function(session)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_accept, "on_socket_accept: %s", self, session, ip, port)
        end)
    end
    return true
end

function WebSocket:on_socket_accept(session)
    local socket = WebSocket(self.host)
    socket:accept(session, session.ip, self.port)
end

function WebSocket:on_socket_error(token, err)
    if self.session then
        self.session = nil
        self.alive   = false
        self.host:on_socket_error(self, token, err)
        self.token = nil
    end
end

function WebSocket:on_socket_recv(session, data)
    local token = session.token
    if self.alive then
        self.alive_time = hive.clock_ms
        self.recvbuf    = self.recvbuf .. data
        while true do
            local frame = self:recv_frame()
            if not frame then
                break
            end
            if frame.error and frame.opcode == 0x8 then
                -- close/error
                self:close()
                self.host:on_socket_error(self, token, frame.data)
            end
            if frame.opcode == 0x9 then
                --Ping
                self:send_frame(true, 0xA, data)
                goto continue
            end
            if frame.opcode == 0xA then
                --Pong
                goto continue
            end
            thread_mgr:fork(function()
                local context = self.context
                if context then
                    thread_mgr:response(context.session_id, frame)
                    return
                end
                local message = self:combine_frame(frame)
                self.host:on_socket_recv(self, token, message)
                self.context = nil
            end)
            :: continue ::
        end
        return
    end
    self.alive   = true
    self.token   = token
    self.session = session
    if self:on_accept_handshake(session, token, data) then
        self.host:on_socket_accept(self, token)
    end
end

--accept
function WebSocket:accept(session, ip, port)
    self.ip, self.port = ip, port
    session.set_timeout(self.timeout)
    session.on_call_text = function(recv_len, data)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_recv, "on_socket_recv: %s", self, session, data)
        end)
    end
    session.on_error     = function(token, err)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
        end)
    end
end

--握手协议
function WebSocket:on_accept_handshake(session, token, data)
    local request = lhttp.create_request()
    if #data == 0 or not request.parse(data) then
        log_err("[WebSocket][on_accept_handshake] http request process failed, close client(token:%s)!", token)
        return self:response(400, "this http request parse error!")
    end
    local headers = request.get_headers()
    local upgrade = headers["Upgrade"]
    if not upgrade or upgrade ~= "websocket" then
        return self:response(400, "can upgrade only to websocket!")
    end
    local connection = headers["Connection"]
    if not connection or connection ~= "Upgrade" then
        return self:response(400, "connection must be upgrade!")
    end
    local version = headers["Sec-WebSocket-Version"]
    if not version or version ~= "13" then
        return self:response(400, "HTTP/1.1 Upgrade Required\r\nSec-WebSocket-Version: 13\r\n\r\n")
    end
    local key = headers["Sec-WebSocket-Key"]
    if not key then
        return self:response(400, "Sec-WebSocket-Key must not be nil!")
    end
    self.url       = request:url()
    local protocol = headers["Sec-WebSocket-Protocol"]
    if protocol then
        local i  = protocol:find(",", 1, true)
        protocol = "Sec-WebSocket-Protocol: " .. protocol:sub(1, i and i - 1)
    end
    local accept   = lb64encode(lsha1(key .. "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"))
    local fmt_text = "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n%s\r\n"
    self:send(sformat(fmt_text, accept, protocol or ""))
    return true
end

--回执
function WebSocket:response(status, response)
    local resp   = lhttp.create_response()
    resp.status  = status
    resp.content = response
    resp.set_header("Content-Type", "text/plain")
    self:send(resp.serialize())
    self:close()
end

--释放数据
function WebSocket:pop(len)
    if len > 0 then
        if #self.recvbuf > len then
            self.recvbuf = ssub(self.recvbuf, len + 1)
        else
            self.recvbuf = ""
        end
    end
end

--peek
function WebSocket:peek(len, offset)
    offset = offset or 0
    if offset + len <= #self.recvbuf then
        return ssub(self.recvbuf, offset + 1, offset + len)
    end
end

--发送数据
function WebSocket:send(data)
    if self.alive and data then
        return self.session.call_text(data) > 0
    end
    log_err("[WebSocket][send] the socket not alive, can't send")
    return false
end

--发送帧
function WebSocket:send_frame(fin, opcode, data)
    local len    = #data
    local finbit = fin and 0x80 or 0
    --服务器回包不需要掩码格式化
    if len < 126 then
        self:send(spack("BB", finbit | opcode, len) .. data)
    elseif len < 0xFFFF then
        self:send(spack(">BBI2", finbit | opcode, 126, len) .. data)
    else
        self:send(spack(">BBI8", finbit | opcode, 127, len) .. data)
    end
end

function WebSocket:send_text(data)
    self:send_frame(true, 0x1, data)
end

function WebSocket:send_binary(data)
    self:send_frame(true, 0x2, data)
end

--接收ws帧
function WebSocket:recv_frame()
    local offset = 2
    local data   = self.recvbuf
    if #data < offset then
        return
    end
    local header, payloadlen = sunpack("BB", data)
    if header & 0x70 ~= 0 then
        return { error = true, data = "Reserved_bits show using undefined extensions" }
    end
    local masklen, packlen = 0, 0
    local fmtlen           = payloadlen & 0x7f
    if payloadlen & 0x80 ~= 0 then
        masklen = 4
    end
    if fmtlen == 126 then
        packlen = 2
    elseif fmtlen == 127 then
        packlen = 8
    end
    if #data < offset + packlen + masklen then
        return
    end
    local data_len = fmtlen
    local frame    = { opcode = header & 0xf, final = header & 0x80 ~= 0 }
    if packlen == 2 then
        data_len = sunpack(">H", self:peek(packlen, offset))
    elseif packlen == 8 then
        data_len = sunpack(">I8", self:peek(packlen, offset))
    end
    offset = offset + packlen
    if masklen > 0 then
        frame.mask = self:peek(masklen, offset)
        offset     = offset + masklen
    end
    if #data < offset + data_len then
        return
    end
    if data_len > 0 then
        frame.data = self:peek(data_len, offset)
        if masklen > 0 then
            frame.data = lxor_byte(frame.data, frame.mask)
        end
    end
    self:pop(data_len + offset)
    return frame
end

--组合帧数据
function WebSocket:combine_frame(frame)
    if frame.final then
        return frame.data
    end
    while true do
        local session_id = thread_mgr:build_session_id()
        self.context     = { session_id = session_id }
        local next_frame = thread_mgr:yield(session_id, "combine_frame", HTTP_CALL_TIMEOUT)
        frame.data       = frame.data .. next_frame.data
        if next_frame.final then
            break
        end
    end
    return frame.data
end

return WebSocket
