-- rpc_client.lua
local tunpack      = table.unpack
local tpack        = table.pack
local log_err      = logger.err
local hxpcall      = hive.xpcall
local hhash_code   = hive.hash_code

local event_mgr    = hive.get("event_mgr")
local socket_mgr   = hive.get("socket_mgr")
local thread_mgr   = hive.get("thread_mgr")
local perfeval_mgr = hive.get("perfeval_mgr")

local FlagMask     = enum("FlagMask")
local KernCode     = enum("KernCode")
local NetwkTime    = enum("NetwkTime")
local SUCCESS      = KernCode.SUCCESS

local RpcClient    = class()
local prop         = property(RpcClient)
prop:reader("ip", nil)
prop:reader("port", nil)
prop:reader("alive", false)
prop:reader("alive_time", 0)
prop:reader("socket", nil)
prop:reader("holder", nil)    --持有者
function RpcClient:__init(holder, ip, port)
    self.holder = holder
    self.port   = port
    self.ip     = ip
end

--调用rpc后续处理
function RpcClient:on_call_router(rpc, send_len, ...)
    if send_len > 0 then
        event_mgr:notify_listener("on_rpc_send", rpc, send_len)
        return true, send_len
    end
    log_err("[RpcClient][on_call_router] rpc %s call [%s] failed! code:%s", rpc, tpack(...), send_len)
    return false
end

--检测存活
function RpcClient:check_lost(clock_ms)
    if clock_ms - self.alive_time > NetwkTime.ROUTER_TIMEOUT then
        self:close()
        return true
    end
end

--发送心跳
function RpcClient:heartbeat(initial)
    if initial then
        local node_info = {
            id         = hive.id,
            index      = hive.index,
            deploy     = hive.deploy,
            service    = hive.service,
            service_id = hive.service_id,
        }
        self:send("rpc_heartbeat", node_info)
        return
    end
    self:send("rpc_heartbeat")
end

--连接服务器
function RpcClient:connect()
    --连接中
    if self.socket then
        return true
    end
    --开始连接
    local socket, cerr = socket_mgr.connect(self.ip, self.port, NetwkTime.CONNECT_TIMEOUT)
    if not socket then
        log_err("[RpcClient][connect] failed to connect: %s:%d err=%s", self.ip, self.port, cerr)
        return false, cerr
    end
    socket.on_call         = function(recv_len, session_id, rpc_flag, source, rpc, ...)
        event_mgr:notify_listener("on_rpc_recv", rpc, recv_len)
        hxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, socket, session_id, rpc_flag, source, rpc, ...)
    end
    socket.call_rpc        = function(session_id, rpc_flag, rpc, ...)
        local send_len = socket.call(session_id, rpc_flag, hive.id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_target     = function(session_id, target, rpc, ...)
        local send_len = socket.forward_target(session_id, FlagMask.REQ, hive.id, target, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.callback_target = function(session_id, target, rpc, ...)
        if target == 0 then
            local send_len = socket.call(session_id, FlagMask.RES, hive.id, rpc, ...)
            return self:on_call_router(rpc, send_len, ...)
        else
            local send_len = socket.forward_target(session_id, FlagMask.RES, hive.id, target, rpc, ...)
            return self:on_call_router(rpc, send_len, ...)
        end
    end
    socket.call_hash       = function(session_id, service_id, hash_key, rpc, ...)
        local hash_value = hhash_code(hash_key)
        local send_len   = socket.forward_hash(session_id, FlagMask.REQ, hive.id, service_id, hash_value, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_random     = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_random(session_id, FlagMask.REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_master     = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_master(session_id, FlagMask.REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_broadcast  = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_broadcast(session_id, FlagMask.REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.call_collect    = function(session_id, service_id, rpc, ...)
        local send_len = socket.forward_broadcast(session_id, FlagMask.REQ, hive.id, service_id, rpc, ...)
        return self:on_call_router(rpc, send_len, ...)
    end
    socket.on_error        = function(token, err)
        self:on_socket_error(token, err)
    end
    socket.on_connect      = function(res)
        if res == "ok" then
            hxpcall(self.on_socket_connect, "on_socket_connect: %s", self, socket, res)
        else
            self:on_socket_error(socket.token, res)
        end
    end
    self.socket            = socket
end

-- 主动关闭连接
function RpcClient:close()
    if self.socket then
        self.socket.close()
        self.alive  = false
        self.socket = nil
    end
end

--心跳回复
function RpcClient:on_heartbeat(qid)
end

--rpc事件
function RpcClient:on_socket_rpc(socket, session_id, rpc_flag, source, rpc, ...)
    self.alive_time = hive.clock_ms
    if rpc == "on_heartbeat" then
        return self:on_heartbeat(...)
    end
    if session_id == 0 or rpc_flag == FlagMask.REQ then
        local function dispatch_rpc_message(...)
            local _<close>  = perfeval_mgr:eval(rpc)
            local rpc_datas = event_mgr:notify_listener(rpc, ...)
            if session_id > 0 then
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
    --log_err("[RpcClient][on_socket_error] socket %s:%s %s!", self.ip, self.port, err)
    thread_mgr:fork(function()
        self.socket = nil
        self.alive  = false
        self.holder:on_socket_error(self, token, err)
    end)
end

--连接成功
function RpcClient:on_socket_connect(socket)
    --log_info("[RpcClient][on_socket_connect] connect to %s:%s success!", self.ip, self.port)
    self.alive      = true
    self.alive_time = hive.clock_ms
    thread_mgr:fork(function()
        self.holder:on_socket_connect(self)
        self:heartbeat(true)
    end)
end

--转发系列接口
function RpcClient:forward_socket(method, session_id, ...)
    if self.alive then
        if self.socket[method](session_id, ...) then
            if session_id > 0 then
                return thread_mgr:yield(session_id, method, NetwkTime.RPC_CALL_TIMEOUT)
            end
            return true, SUCCESS
        end
        log_err("[RpcClient][forward_socket] send failed:ip:%s,port:%s", self.ip, self.port)
        return false, "socket send failed"
    end
    return false, "socket not connected"
end

--直接发送接口
function RpcClient:send(rpc, ...)
    if self.alive then
        self.socket.call_rpc(0, FlagMask.REQ, rpc, ...)
        return true
    end
    return false, "socket not connected"
end

--直接发送接口
function RpcClient:call(rpc, ...)
    if self.alive then
        local session_id = thread_mgr:build_session_id()
        if self.socket.call_rpc(session_id, FlagMask.REQ, rpc, ...) then
            return thread_mgr:yield(session_id, rpc, NetwkTime.RPC_CALL_TIMEOUT)
        end
    end
    return false, "socket not connected"
end

return RpcClient
