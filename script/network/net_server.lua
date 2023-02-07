--net_server.lua
local lcrypt           = require("lcrypt")

local log_err          = logger.err
local log_info         = logger.info
local log_warn         = logger.warn
local hxpcall          = hive.xpcall
local env_number       = environ.number
local signal_quit      = signal.quit

local event_mgr        = hive.get("event_mgr")
local thread_mgr       = hive.get("thread_mgr")
local protobuf_mgr     = hive.get("protobuf_mgr")
local proxy_agent      = hive.get("proxy_agent")
local heval            = hive.eval

local FLAG_REQ         = hive.enum("FlagMask", "REQ")
local FLAG_RES         = hive.enum("FlagMask", "RES")
local FLAG_ZIP         = hive.enum("FlagMask", "ZIP")
local FLAG_ENCRYPT     = hive.enum("FlagMask", "ENCRYPT")
local NETWORK_TIMEOUT  = hive.enum("NetwkTime", "NETWORK_TIMEOUT")
local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local out_press        = environ.status("HIVE_OUT_PRESS")
local out_encrypt      = environ.status("HIVE_OUT_ENCRYPT")
local flow_ctrl        = environ.status("HIVE_FLOW_CTRL")
local flow_cd          = env_number("HIVE_FLOW_CTRL_CD")
local fc_package       = env_number("HIVE_FLOW_CTRL_PACKAGE") / 1000
local fc_bytes         = env_number("HIVE_FLOW_CTRL_BYTES") / 1000

-- Dx协议会话对象管理器
local NetServer        = class()
local prop             = property(NetServer)
prop:reader("ip", "")                   --监听ip
prop:reader("port", 0)                  --监听端口
prop:reader("proto_type", 1)
prop:reader("sessions", {})             --会话列表
prop:reader("session_type", "default")  --会话类型
prop:reader("session_count", 0)         --会话数量
prop:reader("listener", nil)            --监听器
prop:reader("command_cds", {})          --CMD定制CD
prop:accessor("coder", nil)             --编解码对象
prop:accessor("log_client_msg", nil)    --消息日志函数
prop:accessor("timeout", NETWORK_TIMEOUT)
prop:accessor("buff_size", 0)

function NetServer:__init(session_type)
    self.session_type = session_type
    --默认设置pb编解码
    self.coder        = protobuf_mgr
end

--induce：根据index推导port
function NetServer:setup(ip, port, induce)
    -- 开启监听
    if not ip or not port then
        log_err("[NetServer][setup] ip:%s or port:%s is nil", ip, port)
        signal_quit()
        return
    end
    local socket_mgr = hive.get("socket_mgr")
    local real_port  = induce and (port + hive.index - 1) or port
    self.listener    = socket_mgr.listen(ip, real_port, self.proto_type)
    if not self.listener then
        log_err("[NetServer][setup] failed to listen: %s:%d type=%d", ip, real_port, self.proto_type)
        signal_quit()
        return
    end
    self.ip, self.port = ip, real_port
    log_info("[NetServer][setup] start listen at: %s:%d type=%d", ip, real_port, self.proto_type)
    -- 安装回调
    self.listener.on_accept = function(session)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_accept, "on_socket_accept: %s", self, session)
        end)
    end
end

-- 连接回调
function NetServer:on_socket_accept(session)
    self:add_session(session)
    -- 流控配置
    session.fc_packet    = 0
    session.fc_bytes     = 0
    session.last_fc_time = hive.clock_ms
    -- 设置超时(心跳)
    session.set_timeout(self.timeout)
    -- 设置buff长度
    if self.buff_size > 0 then
        session.set_send_buffer_size(self.buff_size)
        session.set_recv_buffer_size(self.buff_size)
    end
    -- 绑定call回调
    session.on_call_pack  = function(recv_len, cmd_id, flag, session_id, data)
        thread_mgr:fork(function()
            session.fc_packet = session.fc_packet + 1
            session.fc_bytes  = session.fc_bytes + recv_len
            proxy_agent:statistics("on_proto_recv", cmd_id, recv_len)
            hxpcall(self.on_socket_recv, "on_socket_recv: %s", self, session, cmd_id, flag, session_id, data)
        end)
    end
    -- 绑定网络错误回调（断开）
    session.on_error      = function(token, err)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
        end)
    end
    session.command_times = {}
    --通知链接成功
    event_mgr:notify_listener("on_socket_accept", session)
end

function NetServer:write(session, cmd_id, data, session_id, flag)
    local body, pflag = self:encode(cmd_id, data, flag)
    if not body then
        log_err("[NetServer][write] encode failed! cmd_id:%s,data:%s", cmd_id, data)
        return false
    end
    -- call lbus
    local send_len = session.call_pack(cmd_id, pflag, session_id or 0, body)
    if send_len > 0 then
        proxy_agent:statistics("on_proto_send", cmd_id, send_len)
        if self.log_client_msg then
            self.log_client_msg(session, cmd_id, data, session_id, send_len, false)
        end
        return true
    end
    --log_err("[NetServer][write] call_pack failed! code:%s", send_len)
    return false
end

-- 广播数据
function NetServer:broadcast(cmd_id, data, filter)
    local body, pflag = self:encode(cmd_id, data, FLAG_REQ)
    if not body then
        log_err("[NetServer][broadcast] encode failed! cmd_id:%s,data:%s", cmd_id, data)
        return false
    end
    for _, session in pairs(self.sessions) do
        if not filter or filter(session) then
            local send_len = session.call_pack(cmd_id, pflag, 0, body)
            if send_len > 0 then
                proxy_agent:statistics("on_proto_send", cmd_id, send_len)
            end
        end
    end
    if self.log_client_msg then
        self.log_client_msg({}, cmd_id, data, 0, #body, false)
    end
    return true
end

-- 发送数据
function NetServer:send_pack(session, cmd_id, data, session_id)
    return self:write(session, cmd_id, data, session_id, FLAG_REQ)
end

-- 回调数据
function NetServer:callback_pack(session, cmd_id, data, session_id)
    return self:write(session, cmd_id, data, session_id, FLAG_RES)
end

-- 发起远程调用
function NetServer:call_pack(session, cmd_id, data)
    local session_id = thread_mgr:build_session_id()
    if not self:write(session, cmd_id, data, session_id, FLAG_REQ) then
        return false
    end
    return thread_mgr:yield(session_id, cmd_id, RPC_CALL_TIMEOUT)
end

function NetServer:encode(cmd_id, data, flag)
    local encode_data = self.coder:encode(cmd_id, data)
    -- 加密处理
    if out_encrypt then
        encode_data = lcrypt.b64_encode(encode_data)
        flag        = flag | FLAG_ENCRYPT
    end
    -- 压缩处理
    if out_press then
        encode_data = lcrypt.lz4_encode(encode_data)
        flag        = flag | FLAG_ZIP
    end
    return encode_data, flag
end

function NetServer:decode(cmd_id, data, flag)
    if not self.coder:verify_cmd(cmd_id) then
        return nil
    end
    local de_data = data
    if flag & FLAG_ZIP == FLAG_ZIP then
        --解压处理
        de_data = lcrypt.lz4_decode(de_data)
    end
    if flag & FLAG_ENCRYPT == FLAG_ENCRYPT then
        --解密处理
        de_data = lcrypt.b64_decode(de_data)
    end
    return self.coder:decode(cmd_id, de_data)
end

-- 配置指定cmd的cd
function NetServer:define_cmd_cd(cmd_id, cd_time)
    self.command_cds[cmd_id] = cd_time
end

-- 查找指定cmd的cdtime
function NetServer:get_cmd_cd(cmd_id)
    return self.command_cds[cmd_id] or flow_cd
end

-- 收到远程调用回调
function NetServer:on_socket_recv(session, cmd_id, flag, session_id, data)
    local clock_ms    = hive.clock_ms
    local cmd_cd_time = self:get_cmd_cd(cmd_id)
    if cmd_cd_time > 0 then
        local command_times = session.command_times
        if command_times[cmd_id] and clock_ms - command_times[cmd_id] < cmd_cd_time then
            log_warn("[NetServer][on_socket_recv] session(%s) trigger cmd(%s) cd ctrl, will be drop.", session.token, cmd_id)
            --协议CD
            return
        end
        command_times[cmd_id] = clock_ms
    end
    session.alive_time   = hive.clock_ms
    -- 解码
    local body, cmd_name = self:decode(cmd_id, data, flag)
    if not body then
        log_warn("[NetServer][on_socket_recv] cmd(%s) parse failed.", cmd_id)
        return
    end
    if session_id == 0 or (flag & FLAG_REQ == FLAG_REQ) then
        local function dispatch_rpc_message(_session, cmd, bd)
            local _<close> = heval(cmd_name)
            if self.log_client_msg then
                self.log_client_msg(session, cmd, bd, session_id, #data, true)
            end
            local result = event_mgr:notify_listener("on_session_cmd", _session, cmd, bd, session_id)
            if not result[1] then
                log_err("[NetServer][on_socket_recv] on_session_cmd failed! cmd_id:%s", cmd_id)
            end
        end
        thread_mgr:fork(dispatch_rpc_message, session, cmd_id, body)
        return
    end
    --异步回执
    thread_mgr:response(session_id, true, body)
end

--检查序列号
function NetServer:check_serial(session)
    -- 流量控制检测
    if flow_ctrl then
        -- 达到检测周期
        local cur_time    = hive.clock_ms
        local escape_time = cur_time - session.last_fc_time
        if escape_time > 10000 then
            -- 检查是否超过配置
            if session.fc_packet / escape_time > fc_package or session.fc_bytes / escape_time > fc_bytes then
                log_warn("[NetServer][check_serial] session trigger package:%s/%s or bytes:%s/%s,escape_time:%s flowctrl line, will be closed.",
                         session.fc_packet, fc_package, session.fc_bytes, fc_bytes, escape_time)
                self:close_session(session)
            end
            session.fc_packet    = 0
            session.fc_bytes     = 0
            session.last_fc_time = cur_time
        end
    end
end

-- 关闭会话
function NetServer:close_session(session)
    if self:remove_session(session.token) then
        session.close()
    end
end

-- 关闭会话
function NetServer:close_session_by_token(token)
    local session = self.sessions[token]
    self:close_session(session)
end

-- 会话被关闭回调
function NetServer:on_socket_error(token, err)
    local session = self:remove_session(token)
    if session then
        thread_mgr:fork(function()
            event_mgr:notify_listener("on_socket_error", session, token, err)
        end)
    end
end

-- 添加会话
function NetServer:add_session(session)
    local token = session.token
    if not self.sessions[token] then
        self.sessions[token] = session
        self.session_count   = self.session_count + 1
        proxy_agent:statistics("on_conn_update", self.session_type, self.session_count)
    end
end

-- 移除会话
function NetServer:remove_session(token)
    local session = self.sessions[token]
    if session then
        self.sessions[token] = nil
        self.session_count   = self.session_count - 1
        proxy_agent:statistics("on_conn_update", self.session_type, self.session_count)
        return session
    end
end

-- 查询会话
function NetServer:get_session_by_token(token)
    return self.sessions[token]
end

return NetServer
