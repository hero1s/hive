--router_server.lua
local log_err      = logger.err
local log_info     = logger.info
local log_warn     = logger.warn
local log_debug    = logger.debug
local sidhash      = service.hash
local sid2nick     = service.id2nick

local FlagMask     = enum("FlagMask")
local KernCode     = enum("KernCode")
local RpcServer    = import("network/rpc_server.lua")

local socket_mgr   = hive.get("socket_mgr")

local RouterServer = singleton()
local prop         = property(RouterServer)
prop:accessor("rpc_server", nil)
prop:accessor("kick_servers", {})
prop:accessor("service_masters", {})
function RouterServer:__init()
    self:setup()
end

function RouterServer:setup()
    local port      = environ.number("HIVE_ROUTER_PORT", 9001)
    --启动server
    self.rpc_server = RpcServer(self, "0.0.0.0", port, true)
    service.make_node(self.rpc_server:get_port())
    socket_mgr.set_router_id(hive.id)
end

--其他服务器节点关闭
function RouterServer:on_client_error(server, server_token, err)
    log_info("[RouterServer][on_client_error] %s lost: %s", server.name or server_token, err)
    local kick_server_id = self.kick_servers[server_token]
    if kick_server_id then
        local format = "[RouterServer][on_socket_error] kick server close! token:%s, name:%s, ip:%s"
        log_warn(format, server_token, server.name, server.ip)
        self.kick_servers[server_token] = nil
        return
    end
    local server_id  = server.id
    local service_id = server.service_id
    if not server_id or not service_id then
        log_debug("[RouterServer][on_client_error] not register:%s", server_token)
        return
    end
    self.rpc_server:broadcast("rpc_service_close", server_id, hive.id)
    local master_id = socket_mgr.map_token(server_id, 0)
    self:broadcast_switch_master(master_id, service_id)
end

--accept事件
function RouterServer:on_client_accept(server)
    log_info("[RouterServer][on_client_accept] new connection, token=%s", server.token)
    server.on_forward_error     = function(session_id, error_msg)
        log_err("[RouterServer][on_client_accept] on_forward_error:%s, session_id=%s,%s", error_msg, session_id, server.name)
        server.call(session_id, FlagMask.RES, hive.id, "on_forward_error", false, KernCode.RPC_UNREACHABLE, error_msg)
    end
    server.on_forward_broadcast = function(session_id, broadcast_num)
        server.call(session_id, FlagMask.RES, hive.id, "on_forward_broadcast", true, KernCode.SUCCESS, broadcast_num)
    end
end

--rpc事件处理
------------------------------------------------------------------
--注册服务器
function RouterServer:service_register(server, id)
    local service_id    = server.service_id
    local server_name   = server.name
    local service_name  = server.service_name
    local service_index = server.index
    local service_hash  = sidhash(service_id)
    local server_token  = server.token
    if not service_name or not service_hash then
        log_err("[RouterServer][service_register] the serivice is not cfg:%s", service_id)
        return
    end
    -- 检查是否顶号
    for exist_token, exist_server in self.rpc_server:iterator() do
        if exist_server.id == id and exist_server.token ~= server_token then
            self.kick_servers[exist_token] = id
            self.rpc_server:send(exist_server, "rpc_service_kickout", hive.id, "service replace")
            log_err("[RouterServer][service_register] service(%s) be kickout, service replace!", server_name)
            break
        end
    end
    --固定hash自动设置为最大index服务[约定固定hash服务的index为连续的1-n,且运行过程中不能扩容]
    local hash_value = service_hash > 0 and service_index or 0
    local master_id  = socket_mgr.map_token(id, server_token, hash_value)
    log_info("[RouterServer][service_register] service: %s,hash:%s", server_name, service_hash)
    self:broadcast_switch_master(master_id, service_id)
    --通知其他服务器
    self:broadcast_service_ready(server, id)
end

-- 广播服务准备
function RouterServer:broadcast_service_ready(server, id)
    local router_id = hive.id
    for _, exist_server in self.rpc_server:iterator() do
        local exist_server_id = exist_server.id
        if exist_server_id and exist_server_id ~= id then
            self.rpc_server:send(exist_server, "rpc_service_ready", id, router_id, server.pid)
            self.rpc_server:send(server, "rpc_service_ready", exist_server_id, router_id, exist_server.pid)
        end
    end
end

-- 广播切换主从
function RouterServer:broadcast_switch_master(server_id, service_id)
    if server_id == self.service_masters[service_id] then
        return
    end
    log_info("[RouterServer][broadcast_switch_master] switch master --> %s", sid2nick(server_id))
    self.service_masters[service_id] = server_id
    self.rpc_server:servicecast(service_id, "rpc_service_master", server_id, hive.id)
end

-- 会话信息
function RouterServer:on_client_register(client, node_info)
    log_debug("[RouterServer][on_client_register] %s", node_info)
    self:service_register(client, node_info.id)
end

hive.router_server = RouterServer()

return RouterServer
