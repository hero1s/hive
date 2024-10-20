--rpc_server.lua
local pairs               = pairs
local tunpack             = table.unpack
local log_err             = logger.err
local log_info            = logger.info
local hxpcall             = hive.xpcall
local signal_quit         = signal.quit
local luabus              = luabus

local FLAG_REQ            = hive.enum("FlagMask", "REQ")
local FLAG_RES            = hive.enum("FlagMask", "RES")
local SUCCESS             = hive.enum("KernCode", "SUCCESS")
local RPC_CALL_TIMEOUT    = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")
local RPCLINK_TIMEOUT     = hive.enum("NetwkTime", "RPCLINK_TIMEOUT")
local RPC_PROCESS_TIMEOUT = hive.enum("NetwkTime", "RPC_PROCESS_TIMEOUT")

local event_mgr           = hive.get("event_mgr")
local update_mgr          = hive.get("update_mgr")
local thread_mgr          = hive.get("thread_mgr")
local proxy_agent         = hive.get("proxy_agent")
local heval               = hive.eval

local RpcServer           = singleton()

local prop                = property(RpcServer)
prop:reader("ip", "")                     --监听ip
prop:reader("port", 0)                    --监听端口
prop:reader("clients", {})
prop:reader("listener", nil)
prop:reader("holder", nil)                --持有者
prop:reader("indexes", {})                --id索引

--induce：根据index推导port
function RpcServer:__init(holder, ip, port, induce)
    if not ip or not port then
        log_err("[RpcServer][setup] ip:{} or port:{} is nil", ip, port)
        signal_quit()
        return
    end
    local real_port = induce and (port + hive.index - 1) or port
    self.listener   = luabus.listen(ip, real_port)
    if not self.listener then
        log_err("[RpcServer][setup] now listen {}:{} failed", ip, real_port)
        signal_quit()
        return
    end
    self.holder        = holder
    self.ip, self.port = ip, real_port
    log_info("[RpcServer][setup] now listen {}:{} success!", ip, real_port)
    self.listener.on_accept = function(client)
        hxpcall(self.on_socket_accept, "on_socket_accept: %s", self, client)
    end
    event_mgr:add_listener(self, "rpc_heartbeat")
    event_mgr:add_listener(self, "rpc_register")
    --注册退出
    update_mgr:attach_quit(self)
end

function RpcServer:on_quit()
    if self.listener then
        log_info("[RpcServer][on_quit]")
        self.listener:close()
    end
end

--rpc事件
function RpcServer:on_socket_rpc(client, rpc, session_id, rpc_flag, source, ...)
    if session_id == 0 or rpc_flag == FLAG_REQ then
        local btime = hive.clock_ms
        local function dispatch_rpc_message(...)
            local _<close>  = heval(rpc)
            local rpc_datas = event_mgr:notify_listener(rpc, client, ...)
            if session_id > 0 then
                local cost_time = hive.clock_ms - btime
                if cost_time > RPC_PROCESS_TIMEOUT then
                    log_err("[RpcServer][on_socket_rpc] rpc:{}, session:{},cost_time:{}", rpc, session_id, cost_time)
                end
                client.call_rpc(session_id, FLAG_RES, rpc, tunpack(rpc_datas))
            end
        end
        thread_mgr:fork(dispatch_rpc_message, ...)
        return
    end
    thread_mgr:response(session_id, ...)
end

--连接关闭
function RpcServer:on_socket_error(token, err)
    log_info("[RpcServer][on_socket_error] token:{},err:{}!", token, err)
    local client = self.clients[token]
    if client then
        self.clients[token] = nil
        if client.id then
            self.indexes[client.id] = nil
            thread_mgr:fork(function()
                self.holder:on_client_error(client, token, err)
            end)
        end
    end
end

--accept事件
function RpcServer:on_socket_accept(client)
    log_info("[RpcServer][on_socket_accept] token:{},ip:{}", client.token, client.ip)
    client.set_timeout(RPCLINK_TIMEOUT)
    self.clients[client.token] = client

    client.call_rpc            = function(session_id, rpc_flag, rpc, ...)
        local send_len = client.call(session_id, rpc_flag, 0, rpc, ...)
        if send_len < 0 then
            proxy_agent:statistics("on_rpc_send", rpc, send_len)
            log_err("[RpcServer][call_rpc] call failed! code:{}", send_len)
            return false
        end
        return true, SUCCESS
    end
    client.on_call             = function(recv_len, session_id, rpc_flag, source, rpc, ...)
        proxy_agent:statistics("on_rpc_recv", rpc, recv_len)
        hxpcall(self.on_socket_rpc, "on_socket_rpc: %s", self, client, rpc, session_id, rpc_flag, source, ...)
    end
    client.on_error            = function(token, err)
        hxpcall(self.on_socket_error, "on_socket_error: %s", self, token, err)
    end
    --通知收到新client
    self.holder:on_client_accept(client)
end

function RpcServer:call(client, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    if client.call_rpc(session_id, FLAG_REQ, rpc, ...) then
        return thread_mgr:yield(session_id, rpc, RPC_CALL_TIMEOUT)
    end
    return false, "rpc server send failed"
end

function RpcServer:send(client, rpc, ...)
    return client.call_rpc(0, FLAG_REQ, rpc, ...)
end

--回调
function RpcServer:callback(client, session_id, ...)
    client.call_rpc(session_id, FLAG_RES, "callback", ...)
end

function RpcServer:call_sid(id, rpc, ...)
    local client = self.indexes[id]
    if client then
        return self:call(client, rpc, ...)
    end
    return false, "service is not exist"
end

function RpcServer:send_sid(id, rpc, ...)
    local client = self.indexes[id]
    if client then
        return self:send(client, rpc, ...)
    end
    return false, "service is not exist"
end

--broadcast接口
function RpcServer:broadcast(filter, rpc, ...)
    local tokens = {}
    for _, client in pairs(self.clients) do
        if not filter or filter(client) then
            tokens[#tokens + 1] = client.token
        end
    end
    luabus.broad_rpc(tokens, FLAG_REQ, 0, rpc, ...)
end

--servicecast接口
function RpcServer:servicecast(service_id, rpc, ...)
    local tokens = {}
    for _, client in pairs(self.clients) do
        if client.id ~= 0 then
            if service_id == 0 or client.service_id == service_id then
                tokens[#tokens + 1] = client.token
            end
        end
    end
    luabus.broad_rpc(tokens, FLAG_REQ, 0, rpc, ...)
end

function RpcServer:service_count(service_id)
    local count = 0
    for _, client in pairs(self.clients) do
        if client.id then
            if service_id == 0 or client.service_id == service_id then
                count = count + 1
            end
        end
    end
    return count
end

function RpcServer:service_nodes(service_id)
    local nodes = {}
    for _, client in pairs(self.clients) do
        if client.id then
            if service_id == 0 or client.service_id == service_id then
                nodes[#nodes + 1] = client.id
            end
        end
    end
    return nodes
end

--获取client
function RpcServer:get_client(token)
    return self.clients[token]
end

--获取client
function RpcServer:get_client_by_id(hive_id)
    return self.indexes[hive_id]
end

--rpc回执
-----------------------------------------------------------------------------
--服务器心跳协议
function RpcServer:rpc_heartbeat(client, status_info, send_time)
    self:send(client, "on_heartbeat", hive.id, send_time, hive.now)
    if client.id then
        self.holder:on_client_beat(client, status_info)
    else
        log_err("[RpcServer][rpc_heartbeat] not register,exception logic:{}", status_info)
        self:disconnect(client)
    end
end

function RpcServer:rpc_register(client, node, ...)
    if not client.id then
        -- 检查重复注册
        local eclient = self.indexes[node.id]
        if eclient then
            local rpc_key = luabus.get_rpc_key()
            log_err("[RpcServer][rpc_register] client({}) be kickout, same service is run!,rpckey:{}", eclient.name, rpc_key)
            self:send(client, "rpc_service_kickout", hive.id, "service replace")
            return
        end
        -- 通知注册
        client.id           = node.id
        client.group        = node.group
        client.index        = node.index
        client.service_id   = node.service_id
        client.service_name = node.service_name
        client.name         = node.name
        client.pid          = node.pid
        self.holder:on_client_register(client, node, ...)
        self.indexes[client.id] = client
    else
        log_err("[RpcServer][rpc_register] repeat register,exception logic:{}", node)
        self:disconnect(client)
    end
end

function RpcServer:disconnect(client)
    self:on_socket_error(client.token, "action-close")
    client.close()
end

return RpcServer
