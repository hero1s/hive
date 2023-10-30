-- rpc_client.lua
local jumphash       = codec.jumphash
local tunpack        = table.unpack
local tpack          = table.pack
local log_err        = logger.err
local log_info       = logger.info
local hxpcall        = hive.xpcall

local event_mgr      = hive.get("event_mgr")
local thread_mgr     = hive.get("thread_mgr")
local proxy_agent    = hive.get("proxy_agent")
local timer_mgr      = hive.get("timer_mgr")
local heval          = hive.eval
local id2nick        = service.id2nick

local FLAG_REQ       = hive.enum("FlagMask", "REQ")
local FLAG_RES       = hive.enum("FlagMask", "RES")
local SUCCESS        = hive.enum("KernCode", "SUCCESS")
local NetwkTime      = enum("NetwkTime")

local SECOND_MS      = hive.enum("PeriodTime", "SECOND_MS")
local HEARTBEAT_TIME = hive.enum("NetwkTime", "HEARTBEAT_TIME")

local RpcClient      = class()
local prop           = property(RpcClient)
prop:reader("ip", nil)
prop:reader("port", nil)
prop:reader("alive", false)
prop:reader("socket", nil)
prop:reader("holder", nil)    --持有者

function RpcClient:__init(holder, ip, port)
    self.holder   = holder
    self.port     = port
    self.ip       = ip
    self.timer_id = timer_mgr:loop(SECOND_MS, function()
        self:check_heartbeat()
    end)
end

function RpcClient:check_heartbeat()
    if not self.holder then
        return
    end
    if self.alive then
        self:heartbeat()
        timer_mgr:set_period(self.timer_id, HEARTBEAT_TIME)
    else
        self:connect()
        timer_mgr:set_period(self.timer_id, SECOND_MS)
    end
end

--调用rpc后续处理
function RpcClient:on_call_router(rpc, send_len, ...)
    if send_len > 0 then
        proxy_agent:statistics("on_rpc_send", rpc, send_len)
        return true, send_len
    end
    log_err("[RpcClient][on_call_router] rpc {} call [{}] failed! code:{}", rpc, tpack(...), send_len)
    return false
end

--发送心跳
function RpcClient:heartbeat()
    local status_info = { id       = hive.node_info.id,
                          is_ready = hive.node_info.is_ready,
                          status   = hive.node_info.status }
    self:send("rpc_heartbeat", status_info, hive.clock_ms)
end

function RpcClient:register(...)
    self:send("rpc_register", hive.node_info, ...)
end

--连接服务器
function RpcClient:connect()
    --连接中
    if self.socket then
        return true
    end
    --开始连接
    local socket, cerr = luabus.connect(self.ip, self.port, NetwkTime.CONNECT_TIMEOUT)
    if not socket then
        log_err("[RpcClient][connect] failed to connect: {}:{} err={}", self.ip, self.port, cerr)
        return false, cerr
    end
    socket.on_call          = function(recv_len, session_id, rpc_flag, source, rpc, ...)
        proxy_agent:statistics("on_rpc_recv", rpc, recv_len)
        hxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, socket, session_id, rpc_flag, source, rpc, ...)
    end
    socket.call_rpc         = function(session_id, rpc_flag, rpc, ...)
        local send_len = socket.call(session_id, rpc_flag, hive.id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_target      = function(session_id, target, rpc, ...)
        local send_len = socket.forward_target(session_id, FLAG_REQ, hive.id, target, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_player      = function(session_id, service_id, player_id, rpc, ...)
        local send_len = socket.forward_player(session_id, FLAG_REQ, hive.id, service_id, player_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.callback_target  = function(session_id, target, rpc, ...)
        if target == 0 then
            local send_len = socket.call(session_id, FLAG_RES, hive.id, rpc, ...)
            return self:on_call_router(rpc, send_len, ...)
        else
            local send_len = socket.forward_target(session_id, FLAG_RES, hive.id, target, rpc, ...)
            return self:on_call_router(rpc, send_len, ...)
        end
    end
    socket.call_hash        = function(session_id, service_id, hash_key, rpc, ...)
        local hash_value = jumphash(hash_key, 0xffff)
        local send_len   = socket.forward_hash(session_id, FLAG_REQ, hive.id, service_id, hash_value, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_master      = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_master(session_id, FLAG_REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_broadcast   = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_broadcast(session_id, FLAG_REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_collect     = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_broadcast(session_id, FLAG_REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.on_error         = function(token, err)
        thread_mgr:fork(function()
            hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
        end)
    end
    socket.on_connect       = function(res)
        thread_mgr:fork(function()
            if res == "ok" then
                hxpcall(self.on_socket_connect, "on_socket_connect: %s", self, socket, res)
            else
                hxpcall(self.on_socket_error, "on_socket_error: %s", self, socket.token, res)
            end
        end)
    end
    --集群转发失败后回调
    socket.on_forward_error = function(session_id, error_msg, source_id)
        thread_mgr:fork(function()
            event_mgr:notify_listener("on_forward_error", session_id, error_msg, source_id)
        end)
    end
    self.socket             = socket
end

-- 主动关闭连接
function RpcClient:close()
    log_err("[RpcClient][close] socket {}:{}!", self.ip, self.port)
    if self.socket then
        self.socket.close()
        self.alive  = false
        self.socket = nil
    end
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
        self.timer_id = nil
    end
end

--心跳回复
function RpcClient:on_heartbeat(hid, send_time)
    local netlag = hive.clock_ms - send_time
    if netlag > SECOND_MS then
        log_err("[RpcClient][on_heartbeat] ({}),netlag:{} ms", id2nick(hid), netlag)
    end
end

--路由失败
function RpcClient:on_forward_error(session_id, ...)
    log_err("[RpcClient][on_forward_error] rpc:{},resp:{}", thread_mgr:get_title(session_id), tpack(...))
    thread_mgr:response(session_id, ...)
end

--rpc事件
function RpcClient:on_socket_rpc(socket, session_id, rpc_flag, source, rpc, ...)
    if rpc == "on_heartbeat" then
        return self:on_heartbeat(...)
    end
    if rpc == "on_forward_error" then
        return self:on_forward_error(session_id, ...)
    end
    if session_id == 0 or rpc_flag == FLAG_REQ then
        local btime = hive.clock_ms
        local function dispatch_rpc_message(...)
            local _<close>  = heval(rpc)
            local rpc_datas = event_mgr:notify_listener(rpc, ...)
            if session_id > 0 then
                local cost_time = hive.clock_ms - btime
                if cost_time > NetwkTime.RPC_PROCESS_TIMEOUT then
                    log_err("[RpcClient][on_socket_rpc] rpc:{}, session:{},cost_time:{}", rpc, session_id, cost_time)
                end
                socket.callback_target(session_id, source, rpc, tunpack(rpc_datas))
            end
        end
        thread_mgr:fork(dispatch_rpc_message, ...)
        return
    end
    thread_mgr:response(session_id, ...)
end

--错误处理
function RpcClient:on_socket_error(token, err)
    log_info("[RpcClient][on_socket_error] socket {}:{},token:{},err:{}!", self.ip, self.port, token, err)
    thread_mgr:fork(function()
        self.socket = nil
        self.alive  = false
        if self.holder then
            self.holder:on_socket_error(self, token, err)
            event_mgr:fire_second(function()
                self:check_heartbeat()
            end)
        end
    end)
end

--连接成功
function RpcClient:on_socket_connect(socket)
    log_info("[RpcClient][on_socket_connect] connect to {}:{} success!", self.ip, self.port)
    thread_mgr:fork(function()
        self.alive = true
        self.holder:on_socket_connect(self)
    end)
end

--转发系列接口
function RpcClient:forward_socket(method, rpc, session_id, ...)
    if self.alive then
        if self.socket[method](session_id, ...) then
            if session_id > 0 then
                return thread_mgr:yield(session_id, rpc, NetwkTime.RPC_CALL_TIMEOUT)
            end
            return true, SUCCESS
        end
        log_err("[RpcClient][forward_socket] send failed:ip:{},port:{}", self.ip, self.port)
        return false, "socket send failed"
    end
    return false, "socket not connected"
end

--直接发送接口
function RpcClient:send(rpc, ...)
    if self.alive then
        self.socket.call_rpc(0, FLAG_REQ, rpc, ...)
        return true
    end
    return false, "socket not connected"
end

--直接发送接口
function RpcClient:call(rpc, ...)
    if self.alive then
        local session_id = thread_mgr:build_session_id()
        if self.socket.call_rpc(session_id, FLAG_REQ, rpc, ...) then
            return thread_mgr:yield(session_id, rpc, NetwkTime.RPC_CALL_TIMEOUT)
        end
    end
    return false, "socket not connected"
end

return RpcClient
