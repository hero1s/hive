--monitor_mgr.lua
import("network/http_client.lua")
import("agent/mongo_agent.lua")
local RpcServer   = import("network/rpc_server.lua")
local HttpServer  = import("network/http_server.lua")

local json_decode = hive.json_decode
local env_get     = environ.get
local env_addr    = environ.addr
local log_warn    = logger.warn
local log_info    = logger.info
local log_debug   = logger.debug
local log_err     = logger.err
local readfile    = io_ext.readfile
local sformat     = string.format
local id2nick     = service.id2nick

local PeriodTime  = enum("PeriodTime")

local router_mgr  = hive.get("router_mgr")
local monitor     = hive.get("monitor")
local thread_mgr  = hive.get("thread_mgr")
local update_mgr  = hive.get("update_mgr")

local MonitorMgr  = singleton()
local prop        = property(MonitorMgr)
prop:reader("rpc_server", nil)
prop:reader("http_server", nil)
prop:reader("monitor_nodes", {})
prop:reader("monitor_lost_nodes", {})
prop:reader("services", {})
prop:reader("log_page", nil)

function MonitorMgr:__init()
    --创建rpc服务器
    local ip, port  = env_addr("HIVE_MONITOR_HOST")
    self.rpc_server = RpcServer(self, ip, port)
    --创建HTTP服务器
    local server    = HttpServer(env_get("HIVE_MONITOR_HTTP"))
    server:register_get("/", "on_log_page", self)
    server:register_get("/status", "on_monitor_status", self)
    server:register_post("/command", "on_monitor_command", self)
    self.http_server = server

    monitor:watch_service_ready(self, "admin")
    --定时更新
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
    log_info("[MonitorMgr][on_client_accept] token:%s", client.token)
end

-- 心跳
function MonitorMgr:on_client_beat(client)

end

-- 会话信息
function MonitorMgr:on_client_register(client, node_info)
    log_debug("[MonitorMgr][on_client_register] node token:%s,%s,%s", client.token, id2nick(node_info.id), node_info)
    node_info.token                       = client.token
    self.monitor_nodes[client.token]      = node_info
    self.monitor_lost_nodes[node_info.id] = nil
    self:add_service(node_info.service_name, node_info)
    --返回所有服务
    for service_name, curr_services in pairs(self.services) do
        if next(curr_services) then
            self.rpc_server:send(client, "rpc_service_changed", service_name, curr_services, {})
        end
    end
    --广播其它服务
    local readys      = {}
    readys[client.id] = { id = node_info.id, ip = node_info.host, port = node_info.port }
    self.rpc_server:broadcast("rpc_service_changed", node_info.service_name, readys, {})
end

-- 会话关闭回调
function MonitorMgr:on_client_error(client, token, err)
    log_warn("[MonitorMgr][on_client_error] node name:%s, id:%s, token:%s,err:%s", id2nick(client.id), client.id, token, err)
    if client.id then
        self.monitor_lost_nodes[client.id] = self.monitor_nodes[token]
        self.monitor_nodes[token]          = nil
        if self:remove_service(client.service_name, client.id) then
            self.rpc_server:broadcast("rpc_service_changed", client.service_name, {}, { [client.id] = { id = client.id } })
        end
    end
end

-- 检测失活
function MonitorMgr:check_lost_node()
    for _, v in pairs(self.monitor_lost_nodes) do
        log_err("[MonitorMgr][check_lost_node] lost service:%s", v)
    end
end

function MonitorMgr:on_minute()
    self:check_lost_node()
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
    log_info("[MonitorMgr][on_service_ready]->id:%s, service_name:%s", service.id2nick(id), service_name)
    self:register_admin()
end

-- 添加服务
function MonitorMgr:add_service(service_name, node)
    local services              = self.services[service_name] or {}
    services[node.id]           = { id = node.id, ip = node.host, port = node.port }
    self.services[service_name] = services
    return true
end

-- 删除服务
function MonitorMgr:remove_service(service_name, id)
    local services = self.services[service_name] or {}
    if services[id] then
        services[id] = nil
        return true
    end
    return false
end

hive.monitor_mgr = MonitorMgr()

return MonitorMgr
