--net_server.lua
local log_err          = logger.err
local log_info         = logger.info
local log_warn         = logger.warn
local hxpcall          = hive.xpcall
local env_number       = environ.number
local signal_quit      = signal.quit
local eproto_type      = luabus.eproto_type
local luabus           = luabus

local event_mgr        = hive.get("event_mgr")
local thread_mgr       = hive.get("thread_mgr")
local proxy_agent      = hive.get("proxy_agent")
local heval            = hive.eval

local FLAG_REQ         = hive.enum("FlagMask", "REQ")
local FLAG_RES         = hive.enum("FlagMask", "RES")
local NETWORK_TIMEOUT  = hive.enum("NetwkTime", "NETWORK_TIMEOUT")
local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local flow_ctrl        = environ.status("HIVE_FLOW_CTRL")
local flow_cd          = env_number("HIVE_FLOW_CTRL_CD", 0)
local fc_package       = env_number("HIVE_FLOW_CTRL_PACKAGE")
local fc_bytes         = env_number("HIVE_FLOW_CTRL_BYTES")

-- Dx协议会话对象管理器
local NetServer        = class()
local prop             = property(NetServer)
prop:reader("ip", "")                   --监听ip
prop:reader("port", 0)                  --监听端口
prop:reader("proto_type", eproto_type.pb)
prop:reader("sessions", {})             --会话列表
prop:reader("session_type", "default")  --会话类型
prop:reader("session_count", 0)         --会话数量
prop:reader("listener", nil)            --监听器
prop:reader("command_cds", {})          --CMD定制CD
prop:reader("codec", nil)               --编解码器
prop:accessor("log_client_msg", nil)    --消息日志函数
prop:accessor("timeout", NETWORK_TIMEOUT)

function NetServer:__init(session_type)
    self.session_type = session_type
    self.codec        = protobuf.pbcodec()
end

--induce：根据index推导port
function NetServer:setup(ip, port, induce)
    -- 开启监听
    if not ip or not port then
        log_err("[NetServer][setup] ip:{} or port:{} is nil", ip, port)
        signal_quit()
        return
    end
    local real_port = induce and (port + hive.index - 1) or port
    self.listener   = luabus.listen(ip, real_port, self.proto_type)
    if not self.listener then
        log_err("[NetServer][setup] failed to listen: {}:{} type={}", ip, real_port, self.proto_type)
        signal_quit()
        return
    end
    self.ip, self.port = ip, real_port
    log_info("[NetServer][setup] start listen at: {}:{} type={}", ip, real_port, self.proto_type)
    -- 安装回调
    self.listener.set_codec(self.codec)
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
    if flow_ctrl then
        session.set_flow_ctrl(fc_package, fc_bytes)
    end
    -- 设置超时(心跳)
    session.set_timeout(self.timeout)
    -- 绑定call回调
    session.on_call_pb    = function(recv_len, cmd_id, flag, session_id, seq_id, data)
        if session.disable then
            return -2
        end
        if seq_id ~= session.seq_id and seq_id ~= 0xff then
            log_warn("[NetServer][on_socket_accept] seq_id:{} != cur:{},ip:{}", seq_id, session.seq_id, session.ip)
            return -1
        end
        session.seq_id = (session.seq_id + 1) & 0xff
        thread_mgr:fork(function()
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
    session.seq_id        = 0
    --通知链接成功
    event_mgr:notify_listener("on_socket_accept", session)
end

function NetServer:write(session, cmd_id, data, session_id, flag)
    -- call luabus
    local send_len = session.call_pb(cmd_id, flag, session_id or 0, data)
    if send_len > 0 then
        proxy_agent:statistics("on_proto_send", cmd_id, send_len)
        if self.log_client_msg then
            self.log_client_msg(session, cmd_id, data, session_id, send_len, false)
        end
        return true
    end
    if send_len < 0 then
        log_err("[NetServer][write] call_pack failed! code:{},cmd_id:{}", send_len, cmd_id)
    end
    return false
end

-- 广播数据
function NetServer:broadcast(cmd_id, data, filter)
    local tokens = {}
    for _, session in pairs(self.sessions) do
        if not filter or filter(session) then
            tokens[#tokens + 1] = session.token
        end
    end
    luabus.broad_group(self.codec, tokens, cmd_id, FLAG_REQ, 0, data)
    if self.log_client_msg then
        self.log_client_msg({}, cmd_id, data, 0, 0, false)
    end
    return true
end

-- 发送数据
function NetServer:send_pack(session, cmd_id, data, session_id)
    local flag = (session_id and session_id > 0) and FLAG_RES or FLAG_REQ
    return self:write(session, cmd_id, data, session_id, flag)
end

-- 发起远程调用
function NetServer:call_pack(session, cmd_id, data)
    local session_id = thread_mgr:build_session_id()
    if not self:write(session, cmd_id, data, session_id, FLAG_REQ) then
        return false
    end
    return thread_mgr:yield(session_id, cmd_id, RPC_CALL_TIMEOUT)
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
        if session.is_command_cd(cmd_id, cmd_cd_time, clock_ms) then
            log_warn("[NetServer][on_socket_recv] session({}) trigger cmd({}) cd ctrl, will be drop.", session.token, cmd_id)
            return
        end
    end
    if session_id == 0 or (flag & FLAG_REQ == FLAG_REQ) then
        local function dispatch_rpc_message(_session, cmd, bd)
            local _<close> = heval(cmd_id)
            if self.log_client_msg then
                self.log_client_msg(_session, cmd, bd, session_id, 0, true)
            end
            local result = event_mgr:notify_listener("on_session_cmd", _session, cmd, bd, session_id)
            if not result[1] then
                log_err("[NetServer][on_socket_recv] on_session_cmd failed! cmd_id:{}", cmd_id)
            end
        end
        thread_mgr:fork(dispatch_rpc_message, session, cmd_id, data)
        return
    end
    --异步回执
    thread_mgr:response(session_id, true, data)
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

function NetServer:disconnect(session)
    self:on_socket_error(session.token, "action-close")
    session.close()
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
        log_info("[NetServer][add_session] session count:{}", self.session_count)
    end
end

-- 移除会话
function NetServer:remove_session(token)
    local session = self.sessions[token]
    if session then
        self.sessions[token] = nil
        self.session_count   = self.session_count - 1
        proxy_agent:statistics("on_conn_update", self.session_type, self.session_count)
        log_info("[NetServer][remove_session] session count:{}", self.session_count)
        return session
    end
end

-- 查询会话
function NetServer:get_session_by_token(token)
    return self.sessions[token]
end

return NetServer
