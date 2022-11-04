--router_server.lua

local mhuge        = math.huge
local log_err      = logger.err
local log_info     = logger.info
local log_warn     = logger.warn
local log_debug    = logger.debug
local signal_quit  = signal.quit
local sidhash      = service.hash
local sid2nick     = service.id2nick
local sid2name     = service.id2name
local sid2index    = service.id2index

local FlagMask     = enum("FlagMask")
local KernCode     = enum("KernCode")
local RpcServer    = import("network/rpc_server.lua")

local socket_mgr   = hive.get("socket_mgr")
local config_mgr   = hive.get("config_mgr")

local RouterServer = singleton()
local prop         = property(RouterServer)
prop:accessor("rpc_server", nil)
prop:accessor("kick_servers", {})
prop:accessor("service_masters", {})
function RouterServer:__init()
    self:setup()
end

function RouterServer:setup()
    local host        = hive.host
    local router_db   = config_mgr:init_table("router", "host")
    local router_conf = router_db:find_one(host)
    if not router_conf then
        log_err("[RouterServer][setup] router_conf is nil host:%s", host)
        signal_quit()
        return
    end
    --因为按host简化配置，可以重复index, 需要重定义routerid
    hive.id         = service.router_id(router_conf.host_id, hive.index)
    hive.name       = service.router_name(router_conf.host_id, hive.index)
    --启动server
    self.rpc_server = RpcServer(self, "0.0.0.0", router_conf.port, true)
    service.make_node(self.rpc_server:get_port())
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
        return
    end
    socket_mgr.map_token(server_id, 0)
    local is_master = (server_id == self.service_masters[service_id])
    if is_master then
        self.service_masters[service_id] = nil
        socket_mgr.set_master(service_id, 0)
    end
    local router_id                    = hive.id
    local new_master, new_master_token = mhuge, nil
    for exist_token, exist_server in self.rpc_server:iterator() do
        self.rpc_server:send(exist_server, "rpc_service_close", server_id, router_id)
        if is_master and exist_server.service_id == service_id and exist_server.id < new_master then
            new_master       = exist_server.id
            new_master_token = exist_token
        end
    end
    --switch master
    if is_master and new_master_token then
        self.service_masters[service_id] = new_master
        socket_mgr.set_master(service_id, new_master_token)
        log_info("[RouterServer][on_socket_error] switch master --> %s", sid2nick(new_master))
        self:broadcast_switch_master(new_master)
    end
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
        log_err("[RouterServer][rpc_service_register] the serivice is not cfg:%s", service_id)
        return
    end
    --固定hash不能超过hash值
    if service_hash > 0 and service_index > service_hash then
        self.kick_servers[server_token] = id
        self.rpc_server:send(server, "rpc_service_kickout", hive.id, "service hash illegal")
        log_warn("[RouterServer][rpc_service_register] service(%s) be kickout, index(%s) > hash(%s)!", server_name, service_index, service_hash)
        return
    end
    -- 检查是否顶号
    for exist_token, exist_server in self.rpc_server:iterator() do
        if exist_server.id == id and exist_server.token ~= server_token then
            self.kick_servers[exist_token] = id
            self.rpc_server:send(exist_server, "rpc_service_kickout", hive.id, "service replace")
            log_warn("[RouterServer][rpc_service_register] service(%s) be kickout, service replace!", server_name)
            break
        end
    end
    socket_mgr.map_token(id, server_token, service_hash)
    log_info("[RouterServer][rpc_service_register] service: %s,hash:%s", server_name, service_hash)
    --switch master
    local group_master = self.service_masters[service_id] or mhuge
    if id < group_master then
        self.service_masters[service_id] = id
        socket_mgr.set_master(service_id, server_token)
        log_info("[RouterServer][rpc_service_register] switch master --> %s", sid2index(id))
        self:broadcast_switch_master(id)
    end
    --通知其他服务器
    self:broadcast_service_ready(server, id)
end

-- 广播服务准备
function RouterServer:broadcast_service_ready(server, id)
    local router_id = hive.id
    for _, exist_server in self.rpc_server:iterator() do
        local exist_server_id = exist_server.id
        if exist_server_id and exist_server_id ~= id then
            self.rpc_server:send(exist_server, "rpc_service_ready", id, router_id)
            self.rpc_server:send(server, "rpc_service_ready", exist_server_id, router_id)
        end
    end
end

-- 广播切换主从
function RouterServer:broadcast_switch_master(server_id)
    local router_id    = hive.id
    local service_name = sid2name(server_id)
    for _, server in self.rpc_server:iterator() do
        if server.id and service_name == sid2name(server.id) then
            self.rpc_server:send(server, "rpc_service_master", server_id, router_id)
        end
    end
end

-- 会话信息
function RouterServer:on_client_register(client, node_info)
    log_debug("[RouterServer][on_client_register] %s", node_info)
    self:service_register(client, node_info.id)
end

hive.router_server = RouterServer()

return RouterServer
