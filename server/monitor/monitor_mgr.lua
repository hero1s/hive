--monitor_mgr.lua
import("network/http_client.lua")
import("agent/mongo_agent.lua")
import("agent/redis_agent.lua")
local RpcServer          = import("network/rpc_server.lua")

local env_addr           = environ.addr
local log_warn           = logger.warn
local log_info           = logger.info
local log_debug          = logger.debug
local log_err            = logger.err
local tinsert            = table.insert
local tsize              = table_ext.size
local id2nick            = service.id2nick
local sid2index          = service.id2index

local ServiceStatus      = enum("ServiceStatus")
local update_mgr         = hive.get("update_mgr")

local delay_time <const> = 20 --网络掉线延迟时间

local MonitorMgr         = singleton()
local prop               = property(MonitorMgr)
prop:reader("rpc_server", nil)
prop:reader("http_server", nil)
prop:reader("monitor_nodes", {})
prop:reader("monitor_lost_nodes", {})
prop:reader("services", {})
prop:reader("open_nacos", false)
prop:reader("changes", {})
prop:reader("close_services", {})

function MonitorMgr:__init()
    --是否nacos做服务发现
    self.open_nacos = environ.status("HIVE_NACOS_OPEN")

    --创建rpc服务器
    local ip, port  = env_addr("HIVE_MONITOR_HOST")
    self.rpc_server = RpcServer(self, ip, port, environ.status("HIVE_ADDR_INDUCE"))

    --定时更新
    update_mgr:attach_second(self)
    update_mgr:attach_minute(self)
end

function MonitorMgr:on_client_accept(client)
    log_info("[MonitorMgr][on_client_accept] token:{},ip:{}", client.token, client.ip)
end

-- 心跳
function MonitorMgr:on_client_beat(client, status_info)
    local node = self.monitor_nodes[client.token]
    if node then
        node.status = status_info.status
        if node.is_ready ~= status_info.is_ready then
            node.is_ready = status_info.is_ready
            --广播其它服务
            if status_info.is_ready then
                self:add_service(node.service_name, node)
            else
                self:remove_service(node.service_name, node.id, hive.now + delay_time, node.pid)
            end
            self.changes[node.service_name] = true
        end
    end
end

-- 会话信息
function MonitorMgr:on_client_register(client, node_info, watch_services)
    client.watch_services = watch_services
    log_debug("[MonitorMgr][on_client_register] node token:{},{},{}", client.token, id2nick(node_info.id), node_info)
    node_info.token                       = client.token
    self.monitor_nodes[client.token]      = node_info
    self.monitor_lost_nodes[node_info.id] = nil
    --返回所有服务
    self:send_all_service_status(client)
    --广播其它服务
    if node_info.is_ready then
        self:add_service(node_info.service_name, node_info)
    end
end

-- 会话关闭回调
function MonitorMgr:on_client_error(client, token, err)
    log_warn("[MonitorMgr][on_client_error] node name:{}, id:{}, token:{},err:{}", id2nick(client.id), client.id, token, err)
    if client.id then
        local node_info = self.monitor_nodes[token]
        local lost_time = hive.now
        if node_info.status < ServiceStatus.HALT and hive.service_status < ServiceStatus.HALT then
            log_err("[MonitorMgr][on_client_error] the run service lost:{},please fast to repair!!!!!", node_info.name)
            self.monitor_lost_nodes[client.id] = node_info
            lost_time                          = hive.now + delay_time
        end
        self.monitor_nodes[token] = nil
        self:remove_service(client.service_name, client.id, lost_time, node_info.pid)
    end
end

-- 检测失活
function MonitorMgr:check_lost_node()
    for _, v in pairs(self.monitor_lost_nodes) do
        log_err("[MonitorMgr][check_lost_node] lost service:{},please fast to repair!!!!!", v)
    end
end

--10s内重连不算掉线
function MonitorMgr:check_close_services()
    for id, v in pairs(self.close_services) do
        local service_name = v.service_name
        --是否重连
        local services     = self.services[service_name]
        if services and services[id] then
            local pid = services[id].pid
            if pid == v.pid then
                log_err("[MonitorMgr][check_close_services] the [{}] network maybe shake,please make sure!!!", id2nick(id))
            else
                log_err("[MonitorMgr][check_close_services] the [{}] has restart!!!", id2nick(id))
                self:broadcast_service_status(service_name, {}, { [id] = { id = id, pid = v.pid } })
            end
            self.close_services[id] = nil
        else
            if hive.now > v.lost_time then
                self.close_services[id] = nil
                self:broadcast_service_status(service_name, {}, { [id] = { id = id, pid = v.pid } })
            end
        end
    end
end

function MonitorMgr:on_second()
    self:check_close_services()
end

function MonitorMgr:on_minute()
    self:check_lost_node()
    self:show_change_services_info()
end

--call
function MonitorMgr:call_by_token(token, rpc, ...)
    local client = self.rpc_server:get_client(token)
    if not client then
        return { code = 1, msg = "node not connect!" }
    end
    local ok, code, res = self.rpc_server:call(client, rpc, ...)
    if not ok then
        return { code = 1, msg = "call moniotor node failed!" }
    end
    return { code = code, msg = res }
end

function MonitorMgr:call_by_sid(sid, rpc, ...)
    local client = self.rpc_server:get_client_by_id(sid)
    if client then
        local ok, code, res = self.rpc_server:call(client, rpc, ...)
        if not ok then
            return { code = 1, msg = "call moniotor node failed!" }
        end
        return { code = code, msg = res }
    end
    return { code = 1, msg = "target is nil" }
end

function MonitorMgr:send_by_sid(sid, rpc, ...)
    local client = self.rpc_server:get_client_by_id(sid)
    if client then
        self.rpc_server:send(client, rpc, ...)
        return { code = 0, msg = "send target success" }
    end
    return { code = 1, msg = "target is nil" }
end

--broadcast
function MonitorMgr:broadcast(rpc, target, ...)
    local service_id = target or 0
    if type(target) == "string" then
        if target == "" or target == "all" then
            service_id = 0
        else
            service_id = service.name2sid(target)
        end
    end
    self.rpc_server:servicecast(service_id, rpc, ...)
    return { code = 0, msg = "broadcast all nodes server!" }
end

-- 添加服务
function MonitorMgr:add_service(service_name, node)
    log_debug("[MonitorMgr][add_service] {},{}", id2nick(node.id), node)
    local services   = self.services[service_name] or {}
    --检测ip唯一
    local service_id = service.name2sid(service_name)
    if service.sole_ip(service_id) then
        for id, v in pairs(services) do
            if v.ip == node.host and v.port == node.port and id ~= node.id then
                log_err("[MonitorMgr][add_service] the service is repeat ip:{},{},ip:[{}:{}]", id2nick(id), id2nick(node.id), v.ip, v.port)
            end
        end
    end
    services[node.id]           = { id = node.id, ip = node.host, port = node.port, is_ready = node.is_ready, pid = node.pid }
    self.services[service_name] = services
    self.changes[service_name]  = true

    local readys                = {}
    readys[node.id]             = services[node.id]
    self:broadcast_service_status(service_name, readys, {})
    return true
end

-- 删除服务
function MonitorMgr:remove_service(service_name, id, lost_time, pid)
    log_info("[MonitorMgr][remove_service] {}", id2nick(id))
    local services = self.services[service_name] or {}
    if services[id] then
        services[id]               = nil
        self.changes[service_name] = true
        --延迟通知
        self.close_services[id]    = { lost_time = lost_time, service_name = service_name, pid = pid }
        return true
    end
    return false
end

-- 通知服务变更
function MonitorMgr:send_all_service_status(client)
    if self.open_nacos then
        return
    end
    log_debug("[MonitorMgr][send_all_service_status] {}", client.name)
    local readys
    for service_name, curr_services in pairs(self.services) do
        if client.watch_services[service_name] then
            readys = {}
            for id, info in pairs(curr_services) do
                if id ~= client.id and info.is_ready then
                    readys[id] = info
                end
            end
            if next(readys) then
                self.rpc_server:send(client, "rpc_service_changed", service_name, readys, {})
            end
        end
    end
end

function MonitorMgr:broadcast_service_status(service_name, readys, closes)
    if self.open_nacos then
        return
    end
    log_debug("[MonitorMgr][broadcast_service_status] {},{},{}", service_name, readys, closes)
    for _, client in self.rpc_server:iterator() do
        if client.id and client.watch_services[service_name] then
            self.rpc_server:send(client, "rpc_service_changed", service_name, readys, closes)
        end
    end
end

function MonitorMgr:query_services(service_name)
    if #service_name > 1 then
        local services = self.services[service_name] or {}
        local sids     = {}
        for id, v in pairs(services) do
            tinsert(sids, sid2index(id))
        end
        return sids, #sids
    else
        local sids, count = {}, 0
        for sname, curr_services in pairs(self.services) do
            sids[sname] = tsize(curr_services)
            count       = count + sids[sname]
        end
        return sids, count
    end
end

function MonitorMgr:show_change_services_info()
    if next(self.changes) then
        for service_name, _ in pairs(self.changes) do
            local sids = self:query_services(service_name)
            log_debug("[MonitorMgr][show_services_info] [{}],count:{},list:{}", service_name, #sids, sids)
        end
        self.changes = {}
    end
end

hive.monitor_mgr = MonitorMgr()

return MonitorMgr
