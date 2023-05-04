local lcrypt       = require("lcrypt")
local log_err      = logger.err
local hxpcall      = hive.xpcall
local b64_encode   = lcrypt.b64_encode
local b64_decode   = lcrypt.b64_decode
local lz4_encode   = lcrypt.lz4_encode
local lz4_decode   = lcrypt.lz4_decode

local proxy_agent  = hive.get("proxy_agent")
local socket_mgr   = hive.get("socket_mgr")
local thread_mgr   = hive.get("thread_mgr")
local protobuf_mgr = hive.get("protobuf_mgr")
local heval        = hive.eval

local FlagMask     = enum("FlagMask")
local NetwkTime    = enum("NetwkTime")

local out_press    = environ.status("HIVE_OUT_PRESS")
local out_encrypt  = environ.status("HIVE_OUT_ENCRYPT")

local NetClient    = class()
local prop         = property(NetClient)
prop:reader("ip", nil)
prop:reader("port", nil)
prop:reader("alive", false)
prop:reader("alive_time", 0)
prop:reader("proto_type", 1)
prop:reader("socket", nil)          --连接成功对象
prop:reader("holder", nil)          --持有者
prop:reader("wait_list", {})        --等待协议列表
prop:accessor("decoder", nil)       --解码函数
prop:accessor("encoder", nil)       --编码函数

function NetClient:__init(holder, ip, port)
    self.holder = holder
    self.port   = port
    self.ip     = ip
end

-- 发起连接
function NetClient:connect(block)
    if self.socket then
        return true
    end
    local socket, cerr = socket_mgr.connect(self.ip, self.port, NetwkTime.CONNECT_TIMEOUT, self.proto_type)
    if not socket then
        log_err("[NetClient][connect] failed to connect: %s:%d type=%d, err=%s", self.ip, self.port, self.proto_type, cerr)
        return false, cerr
    end
    --设置阻塞id
    local block_id      = block and thread_mgr:build_session_id()
    -- 调用成功，开始安装回调函数
    socket.on_connect   = function(res)
        local succes = (res == "ok")
        thread_mgr:fork(function()
            if not succes then
                hxpcall(self.on_socket_error, "on_socket_error: %s", self, socket.token, res)
            else
                hxpcall(self.on_socket_connect, "on_socket_connect: %s", self, socket)
            end
        end)
        if block_id then
            --阻塞回调
            thread_mgr:response(block_id, succes, res)
        end
    end
    socket.on_call_pack = function(recv_len, cmd_id, flag, session_id, data)
        thread_mgr:fork(function()
            proxy_agent:statistics("on_proto_recv", cmd_id, recv_len)
            hxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, socket, cmd_id, flag, session_id, data)
        end)
    end
    socket.on_error     = function(token, err)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
        end)
    end
    self.socket         = socket
    --阻塞模式挂起
    if block_id then
        return thread_mgr:yield(block_id, "connect", NetwkTime.CONNECT_TIMEOUT)
    end
    return true
end

function NetClient:get_token()
    return self.socket and self.socket.token
end

function NetClient:encode(cmd_id, data, flag)
    local encode_data
    if self.encoder then
        encode_data = self.encoder(cmd_id, data)
    else
        encode_data = protobuf_mgr:encode(cmd_id, data)
    end
    -- 加密处理
    if out_encrypt then
        encode_data = b64_encode(encode_data)
        flag        = flag | FlagMask.ENCRYPT
    end
    -- 压缩处理
    if out_press then
        encode_data = lz4_encode(encode_data)
        flag        = flag | FlagMask.ZIP
    end
    return encode_data, flag
end

function NetClient:decode(cmd_id, data, flag)
    local decode_data = data
    if flag & FlagMask.ZIP == FlagMask.ZIP then
        --解压处理
        decode_data = lz4_decode(decode_data)
    end
    if flag & FlagMask.ENCRYPT == FlagMask.ENCRYPT then
        --解密处理
        decode_data = b64_decode(decode_data)
    end
    if self.decoder then
        return self.decoder(cmd_id, decode_data)
    else
        return protobuf_mgr:decode(cmd_id, decode_data)
    end
end

function NetClient:on_socket_rpc(socket, cmd_id, flag, session_id, data)
    self.alive_time      = hive.clock_ms
    local body, cmd_name = self:decode(cmd_id, data, flag)
    if not body then
        log_err("[NetClient][on_socket_rpc] decode failed! cmd_id:%s，data:%s", cmd_id, data)
        return
    end
    if session_id == 0 or (flag & FlagMask.REQ == FlagMask.REQ) then
        -- 执行消息分发
        local function dispatch_rpc_message()
            local _<close> = heval(cmd_name)
            self.holder:on_socket_rpc(self, cmd_id, body, session_id)
        end
        thread_mgr:fork(dispatch_rpc_message)
        --等待协议处理
        local wait_session_id = self.wait_list[cmd_id]
        if wait_session_id then
            self.wait_list[cmd_id] = nil
            thread_mgr:response(wait_session_id, true)
        end
        return
    end
    --异步回执
    thread_mgr:response(session_id, true, body)
end

-- 主动关闭连接
function NetClient:close()
    if self.socket then
        self.socket.close()
        self.alive  = false
        self.socket = nil
    end
end

function NetClient:write(cmd_id, data, session_id, flag)
    if not self.alive then
        log_err("[NetClient][write] the socket is not alive! cmd_id:%s", cmd_id)
        return false
    end
    local body, pflag = self:encode(cmd_id, data, flag)
    if not body then
        log_err("[NetClient][write] encode failed! cmd_id:%s,data:%s", cmd_id, data)
        return false
    end
    -- call lbus
    local send_len = self.socket.call_pack(cmd_id, pflag, session_id or 0, body)
    if send_len < 0 then
        log_err("[NetClient][write] call_pack failed! code:%s,cmd_id:%s,len:%s", send_len, cmd_id, #body)
        return false
    end
    return true
end

-- 发送数据
function NetClient:send_pack(cmd_id, data, session_id)
    return self:write(cmd_id, data, session_id, FlagMask.REQ)
end

-- 回调数据
function NetClient:callback_pack(cmd_id, data, session_id)
    return self:write(cmd_id, data, session_id, FlagMask.RES)
end

-- 发起远程调用
function NetClient:call_pack(cmd_id, data)
    local session_id = thread_mgr:build_session_id()
    if not self:write(cmd_id, data, session_id, FlagMask.REQ) then
        return false
    end
    return thread_mgr:yield(session_id, cmd_id, NetwkTime.RPC_CALL_TIMEOUT)
end

-- 等待远程调用
function NetClient:wait_pack(cmd_id, time)
    local session_id       = thread_mgr:build_session_id()
    self.wait_list[cmd_id] = session_id
    return thread_mgr:yield(session_id, cmd_id, time)
end

-- 连接成回调
function NetClient:on_socket_connect(socket)
    self.alive      = true
    self.alive_time = hive.clock_ms
    self.holder:on_socket_connect(self)
end

-- 连接关闭回调
function NetClient:on_socket_error(token, err)
    if self.socket then
        self.socket    = nil
        self.alive     = false
        self.wait_list = {}
        self.holder:on_socket_error(self, token, err)
    end
end

return NetClient
