--monitor_mgr.lua
import("network/http_client.lua")
import("agent/mongo_agent.lua")
import("agent/redis_agent.lua")
local RpcServer          = import("network/rpc_server.lua")
local HttpServer         = import("network/http_server.lua")

local json_decode        = hive.json_decode
local env_get            = environ.get
local env_addr           = environ.addr
local log_warn           = logger.warn
local log_info           = logger.info
local log_debug          = logger.debug
local log_err            = logger.err
local readfile           = io_ext.readfile
local sformat            = string.format
local tinsert            = table.insert
local id2nick            = service.id2nick
local sid2index          = service.id2index

local PeriodTime         = enum("PeriodTime")
local ServiceStatus      = enum("ServiceStatus")

local router_mgr         = hive.get("router_mgr")
local monitor            = hive.get("monitor")
local thread_mgr         = hive.get("thread_mgr")
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
prop:reader("log_page", nil)
prop:reader("changes", {})
prop:reader("close_services", {})

function MonitorMgr:__init()
    --是否nacos做服务发现
    self.open_nacos = environ.status("HIVE_NACOS_OPEN")

    --创建rpc服务器
    local ip, port  = env_addr("HIVE_MONITOR_HOST")
    self.rpc_server = RpcServer(self, ip, port, environ.status("HIVE_ADDR_INDUCE"))
    --创建HTTP服务器
    local server    = HttpServer(env_get("HIVE_MONITOR_HTTP"))
    server:register_get("/", "on_log_page", self)
    server:register_get("/status", "on_monitor_status", self)
    server:register_post("/command", "on_monitor_command", self)
    self.http_server = server

    monitor:watch_service_ready(self, "admin")
    --定时更新
    update_mgr:attach_second(self)
    update_mgr:attach_minute(self)
end

function MonitorMgr:register_admin()
    local host      = env_get("HIVE_HOST_IP")
    local http_addr = sformat("%s:%d", host, self.http_server:get_port())
    thread_mgr:success_call(PeriodTime.SECOND_MS, function()
        local ok, code = router_mgr:call_admin_master("rpc_register_monitor", http_addr)
        if hive.success(code, ok) then
            return ok
        end
        log_warn("[MonitorMgr][register_admin] rpc_register_monitor fail:%s,%s", ok, code)
        return false
    end, PeriodTime.SECOND_5_MS)
end

function MonitorMgr:on_client_accept(client)
    log_info("[MonitorMgr][on_client_accept] token:%s,ip:%s", client.token, client.ip)
end

-- 心跳
function MonitorMgr:on_client_beat(client, node_info)
    local node = self.monitor_nodes[client.token]
    if node then
        if node.is_ready ~= node_info.is_ready then
            --广播其它服务
            if node_info.is_ready then
                self:add_service(node.service_name, node, client.token)
            else
                self:remove_service(node.service_name, node.id, hive.now + delay_time, node.pid)
            end
            node.is_ready                   = node_info.is_ready
            self.changes[node.service_name] = true
        end
        node.status = node_info.status
    end
end

-- 会话信息
function MonitorMgr:on_client_register(client, node_info)
    log_debug("[MonitorMgr][on_client_register] node token:%s,%s,%s", client.token, id2nick(node_info.id), node_info)
    node_info.token                       = client.token
    self.monitor_nodes[client.token]      = node_info
    self.monitor_lost_nodes[node_info.id] = nil
    --返回所有服务
    self:send_all_service_status(client)
    --广播其它服务
    if node_info.is_ready then
        self:add_service(node_info.service_name, node_info, client.token)
    end
end

-- 会话关闭回调
function MonitorMgr:on_client_error(client, token, err)
    log_warn("[MonitorMgr][on_client_error] node name:%s, id:%s, token:%s,err:%s", id2nick(client.id), client.id, token, err)
    if client.id then
        local node_info = self.monitor_nodes[token]
        local lost_time = hive.now
        if node_info.status < ServiceStatus.HALT and hive.service_status < ServiceStatus.HALT then
            log_err("[MonitorMgr][on_client_error] the run service lost:%s,please fast to repair!!!!!", node_info.name)
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
        log_err("[MonitorMgr][check_lost_node] lost service:%s,please fast to repair!!!!!", v)
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
                log_err("[MonitorMgr][check_close_services] the [%s] network maybe shake,please make sure!!!", id2nick(id))
            else
                log_err("[MonitorMgr][check_close_services] the [%s] has restart!!!", id2nick(id))
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
    self.log_page = nil
end

--gm_page
function MonitorMgr:on_log_page(url, querys, request)
    if not self.log_page then
        local html_path = hive.import_file_dir("monitor/monitor_mgr.lua") .. "/log_page.html"
        self.log_page   = readfile(html_path)
        if not self.log_page then
            log_err("[MonitorMgr][on_log_page] load html faild:%s", html_path)
        end
    end
    return self.log_page, { ["Access-Control-Allow-Origin"] = "*" }
end

-- status查询
function MonitorMgr:on_monitor_status(url, querys, headers)
    return self.monitor_nodes
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

-- command处理
function MonitorMgr:on_monitor_command(url, body, request)
    log_debug("[MonitorMgr][on_monitor_command]: %s", body)
    --执行函数
    local function handler_cmd(jbody)
        local data_req = json_decode(jbody)
        if data_req.token then
            return self:call_by_token(data_req.token, data_req.rpc, data_req.data)
        end
        return self:broadcast(data_req.rpc, data_req.service_id, data_req.data)
    end
    --开始执行
    local ok, res = pcall(handler_cmd, body)
    if not ok then
        log_warn("[MonitorMgr:on_monitor_post] pcall: %s", res)
        return { code = 1, msg = res }
    end
    return res
end

-- GM服务已经ready
function MonitorMgr:on_service_ready(id, service_name)
    log_info("[MonitorMgr][on_service_ready]->id:%s, service_name:%s", id2nick(id), service_name)
    self:register_admin()
end

-- 添加服务
function MonitorMgr:add_service(service_name, node, token)
    log_debug("[MonitorMgr][add_service] %s,%s", id2nick(node.id), node)
    local services   = self.services[service_name] or {}
    --检测ip唯一
    local service_id = service.name2sid(service_name)
    if service.sole_ip(service_id) then
        for id, v in pairs(services) do
            if v.ip == node.host and v.port == node.port and id ~= node.id then
                log_err("[MonitorMgr][add_service] the service is repeat ip:%s,%s,ip:[%s:%s]", id2nick(id), id2nick(node.id), v.ip, v.port)
            end
        end
    end
    services[node.id]           = { id = node.id, ip = node.host, port = node.port, is_ready = node.is_ready, token = token, pid = node.pid }
    self.services[service_name] = services
    self.changes[service_name]  = true

    local readys                = {}
    readys[node.id]             = services[node.id]
    self:broadcast_service_status(service_name, readys, {})
    return true
end

-- 删除服务
function MonitorMgr:remove_service(service_name, id, lost_time, pid)
    log_info("[MonitorMgr][remove_service] %s", id2nick(id))
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
    log_debug("[MonitorMgr][send_all_service_status] %s", client.name)
    local readys
    for service_name, curr_services in pairs(self.services) do
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

function MonitorMgr:broadcast_service_status(service_name, readys, closes)
    if self.open_nacos then
        return
    end
    log_debug("[MonitorMgr][broadcast_service_status] %s,%s,%s", service_name, readys, closes)
    self.rpc_server:servicecast(0, "rpc_service_changed", service_name, readys, closes)
end

function MonitorMgr:query_services(service_name)
    local services = self.services[service_name] or {}
    local sids     = {}
    for id, v in pairs(services) do
        tinsert(sids, sid2index(id))
    end
    return sids
end

function MonitorMgr:show_change_services_info()
    if next(self.changes) then
        for service_name, _ in pairs(self.changes) do
            local sids = self:query_services(service_name)
            log_debug("[MonitorMgr][show_services_info] [%s],count:%s,list:%s", service_name, #sids, sids)
        end
        self.changes = {}
    end
end

hive.monitor_mgr = MonitorMgr()

return MonitorMgr
