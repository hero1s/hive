--rpc_server.lua
local next          = next
local pairs         = pairs
local tunpack       = table.unpack
local log_err       = logger.err
local log_info      = logger.info
local hxpcall       = hive.xpcall
local signalquit    = signal.quit

local FlagMask      = enum("FlagMask")
local KernCode      = enum("KernCode")
local NetwkTime     = enum("NetwkTime")
local SUCCESS       = KernCode.SUCCESS

local event_mgr     = hive.get("event_mgr")
local thread_mgr    = hive.get("thread_mgr")
local socket_mgr    = hive.get("socket_mgr")
local perfeval_mgr  = hive.get("perfeval_mgr")

local RpcServer = singleton()

local prop = property(RpcServer)
prop:reader("ip", "")                     --监听ip
prop:reader("port", 0)                    --监听端口
prop:reader("clients", {})
prop:reader("listener", nil)
function RpcServer:__init()
end

--初始化
--induce：根据index推导port
function RpcServer:setup(ip, port, induce)
    if not ip or not port then
        log_err("[RpcServer][setup] ip:%s or port:%s is nil", ip, port)
        signalquit()
    end
    local real_port = induce and (port + hive.index - 1) or port
    self.listener = socket_mgr.listen(ip, real_port)
    if not self.listener then
        log_err("[RpcServer][setup] now listen %s:%s failed", ip, real_port)
        signalquit()
    end
    self.ip, self.port = ip, real_port
    log_info("[RpcServer][setup] now listen %s:%s success!", ip, real_port)
    self.listener.on_accept = function(client)
        hxpcall(self.on_socket_accept, "on_socket_accept: %s", self, client)
    end
    event_mgr:add_listener(self, "rpc_heartbeat")
end

--rpc事件
function RpcServer:on_socket_rpc(client, rpc, session_id, rpc_flag, source, ...)
    client.alive_time = hive.now
    if session_id == 0 or rpc_flag == FlagMask.REQ then
        local function dispatch_rpc_message(...)
            local _<close> = perfeval_mgr:eval(rpc)
            local rpc_datas = event_mgr:notify_listener(rpc, client, ...)
            if session_id > 0 then
                client.call_rpc(session_id, FlagMask.RES, rpc, tunpack(rpc_datas))
            end
        end
        thread_mgr:fork(dispatch_rpc_message, ...)
        return
    end
    thread_mgr:response(session_id, ...)
end

--连接关闭
function RpcServer:on_socket_error(token, err)
    local client = self.clients[token]
    if client then
        self.clients[token] = nil
        event_mgr:notify_listener("on_socket_error", client, token, err)
    end
end

--accept事件
function RpcServer:on_socket_accept(client)
    client.set_timeout(NetwkTime.ROUTER_TIMEOUT)
    self.clients[client.token] = client

    client.call_rpc = function(session_id, rpc_flag, rpc, ...)
        local send_len = client.call(session_id, rpc_flag, 0, rpc, ...)
        if send_len < 0 then
            event_mgr:notify_listener("on_rpc_send", rpc, send_len)
            log_err("[RpcServer][call_rpc] call failed! code:%s", send_len)
            return false
        end
        return true, SUCCESS
    end
    client.on_call = function(recv_len, session_id, rpc_flag, source, rpc, ...)
        event_mgr:notify_listener("on_rpc_recv", rpc, recv_len)
        hxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, client, rpc, session_id, rpc_flag, source, ...)
    end
    client.on_error = function(token, err)
        hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
    end
    --通知收到新client
    event_mgr:notify_listener("on_socket_accept", client)
end

--send接口
function RpcServer:call(client, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    if client.call_rpc(session_id, FlagMask.REQ, rpc, ...) then
        return thread_mgr:yield(session_id, rpc, NetwkTime.RPC_CALL_TIMEOUT)
    end
    return false, "rpc server send failed"
end

--send接口
function RpcServer:send(client, rpc, ...)
    return client.call_rpc(0, FlagMask.REQ, rpc, ...)
end

--broadcast接口
function RpcServer:broadcast(rpc, ...)
    for _, client in pairs(self.clients) do
        client.call_rpc(0, FlagMask.REQ, rpc, ...)
    end
end

--获取client
function RpcServer:get_client(token)
    return self.clients[token]
end

--获取client
function RpcServer:get_client_by_id(hive_id)
    for token, client in pairs(self.client) do
        if client.id == hive_id then
            return client
        end
    end
end

--迭代器
function RpcServer:iterator()
    local token = nil
    local clients = self.clients
    local function iter()
        token = next(clients, token)
        if token then
            return token, clients[token]
        end
    end
    return iter
end

--rpc回执
-----------------------------------------------------------------------------
--服务器心跳协议
function RpcServer:rpc_heartbeat(client, node_info)
    self:send(client, "on_heartbeat", hive.id)
    if node_info then
        client.id = node_info.id
        client.service_id = node_info.service_id
        event_mgr:notify_listener("on_socket_info", client, node_info)
    end
end

return RpcServer
