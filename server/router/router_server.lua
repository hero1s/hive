--router_server.lua

local mhuge         = math.huge
local log_err       = logger.err
local log_info      = logger.info
local log_warn      = logger.warn
local signalquit    = signal.quit
local env_get       = environ.get
local sidhash       = service.hash
local sid2sid       = service.id2sid
local sid2nick      = service.id2nick
local sid2name      = service.id2name
local sid2index     = service.id2index

local FlagMask      = enum("FlagMask")
local KernCode      = enum("KernCode")
local RpcServer     = import("network/rpc_server.lua")

local event_mgr     = hive.get("event_mgr")
local socket_mgr    = hive.get("socket_mgr")
local config_mgr    = hive.get("config_mgr")

local RouterServer = singleton()
local prop = property(RouterServer)
prop:accessor("rpc_server", nil)
prop:accessor("kick_servers", {})
prop:accessor("service_masters", {})
function RouterServer:__init()
    self:setup()
end

function RouterServer:setup()
    local host = env_get("HIVE_HOST_IP")
    local router_db = config_mgr:init_table("router", "host")
    local router_conf = router_db:find_one(host)
    if not router_conf then
        log_err("[RouterServer][setup] router_conf is nil host:%s", host)
        signalquit()
        return
    end
    --重定义routerid
    hive.id = service.router_id(router_conf.host_id, hive.index)
    hive.name = service.router_name(router_conf.host_id, hive.index)
    --启动server
    self.rpc_server = RpcServer()
    self.rpc_server:setup(host, router_conf.port, true)
    --监听事件
    event_mgr:add_listener(self, "on_socket_info")
    event_mgr:add_listener(self, "on_socket_error")
    event_mgr:add_listener(self, "on_socket_accept")
    event_mgr:add_listener(self, "rpc_service_register")
end

--其他服务器节点关闭
function RouterServer:on_socket_error(server, server_token, err)
    log_info("[RouterServer][on_socket_error] %s lost: %s", server.name or server_token, err)
    local kick_server_id = self.kick_servers[server_token]
    if kick_server_id then
        local format = "[RouterServer][on_socket_error] kick server close! token:%s, name:%s, ip:%s"
        log_warn(format, server_token,  server.name, server.ip)
        self.kick_servers[server_token] = nil
        return
    end
    local server_id = server.id
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
    local router_id = hive.id
    local new_master, new_master_token = mhuge, nil
    for exist_token, exist_server in self.rpc_server:iterator() do
        self.rpc_server:send(exist_server, "rpc_service_close", server_id, router_id)
        if is_master and exist_server.service_id == service_id and exist_server.id < new_master then
            new_master = exist_server.id
            new_master_token = exist_token
        end
    end
    --switch master
    if is_master and new_master_token then
        self.service_masters[service_id] = new_master
        socket_mgr.set_master(service_id, new_master_token)
        log_info("[RouterServer][on_socket_error] switch master --> %s", sid2nick(new_master))
    end
end

--accept事件
function RouterServer:on_socket_accept(server)
    --log_info("[RouterServer][on_socket_accept] new connection, token=%s", server.token)
    server.on_forward_error = function(session_id)
        log_err("[RouterServer][on_socket_accept] on_forward_error, session_id=%s,%s", session_id,sid2nick(server.id))
        server.call(session_id, FlagMask.RES, hive.id, "on_forward_error", false, KernCode.RPC_UNREACHABLE, "router con't find target!")
    end
    server.on_forward_broadcast = function(session_id, broadcast_num)
        server.call(session_id, FlagMask.RES, hive.id, "on_forward_broadcast", true, KernCode.SUCCESS, broadcast_num)
    end
end

--rpc事件处理
------------------------------------------------------------------
--注册服务器
function RouterServer:rpc_service_register(server, id)
    if not server.id then
        local service_id = sid2sid(id)
        local server_name = sid2nick(id)
        local servive_name = sid2name(id)
        local servive_index = sid2index(id)
        local service_hash = sidhash(service_id)
        local server_token = server.token
        --固定hash不能超过hash值
        if service_hash > 0 and servive_index > service_hash then
            self.kick_servers[server_token] = id
            self.rpc_server:send(server, "rpc_service_kickout", hive.id, "service hash illegal")
            log_warn("[RouterServer][rpc_service_register] service(%s) be kickout, index(%s) > hash(%s)!", server_name, servive_index, service_hash)
            return
        end
        -- 检查是否顶号
        for exist_token, exist_server in self.rpc_server:iterator() do
            if exist_server.id == id then
                self.kick_servers[exist_token] = id
                self.rpc_server:send(exist_server, "rpc_service_kickout", hive.id, "service replace")
                log_warn("[RouterServer][rpc_service_register] service(%s) be kickout, service replace!", server_name)
                break
            end
        end
        server.id = id
        server.name = server_name
        server.service_id = service_id
        server.servive_name = servive_name
        socket_mgr.map_token(id, server_token, service_hash)
        log_info("[RouterServer][rpc_service_register] service: %s,hash:%s", server_name,service_hash)
        --switch master
        local group_master = self.service_masters[service_id] or mhuge
        if id < group_master then
            self.service_masters[service_id] = id
            socket_mgr.set_master(service_id, server_token)
            log_info("[RouterServer][rpc_service_register] switch master --> %s", server_name)
        end
        --通知其他服务器
        local router_id = hive.id
        for _, exist_server in self.rpc_server:iterator() do
            local exist_server_id = exist_server.id
            if exist_server_id and exist_server_id ~= id then
                self.rpc_server:send(exist_server, "rpc_service_ready", id, router_id)
                self.rpc_server:send(server, "rpc_service_ready", exist_server_id, router_id)
            end
        end
    end
end

-- 会话信息
function RouterServer:on_socket_info(client, node_info)
end

hive.router_server = RouterServer()

return RouterServer
