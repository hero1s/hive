--monitor_mgr.lua
local log_page = nil
import("network/http_client.lua")
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

local PeriodTime  = enum("PeriodTime")

local router_mgr  = hive.get("router_mgr")
local thread_mgr  = hive.get("thread_mgr")
local proxy_agent = hive.get("proxy_agent")
local timer_mgr   = hive.get("timer_mgr")

local MonitorMgr  = singleton()
local prop        = property(MonitorMgr)
prop:reader("rpc_server", nil)
prop:reader("http_server", nil)
prop:reader("monitor_nodes", {})
prop:reader("monitor_lost_nodes", {})

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

    --检测失活
    timer_mgr:loop(PeriodTime.MINUTE_MS, function()
        self:check_lost_node()
    end)

    router_mgr:watch_service_ready(self, "admin")
end

function MonitorMgr:register_admin()
    --上报自己
    local admin_url = env_get("HIVE_ADMIN_HTTP")
    if admin_url then
        local host      = env_get("HIVE_HOST_IP")
        local purl      = sformat("%s/monitor", admin_url)
        local http_addr = sformat("%s:%d", host, self.http_server:get_port())
        thread_mgr:success_call(PeriodTime.SECOND_MS, function()
            local ok, status, res = proxy_agent:post(purl, { addr = http_addr })
            if ok and status == 200 then
                ok, res = json_decode(res, true)
                if ok and res.code == 0 then
                    return true
                end
            end
            log_warn("post monitor:%s fail:%s,%s,%s", purl, ok, status, res)
            return false
        end)
    end
end

function MonitorMgr:on_client_accept(client)
    log_info("[MonitorMgr][on_client_accept] token:%s", client.token)
end

-- 会话信息
function MonitorMgr:on_client_register(client, node_info)
    log_info("[MonitorMgr][on_client_register] node token:%s,%s", client.token, node_info.name)
    node_info.token                       = client.token
    self.monitor_nodes[client.token]      = node_info
    self.monitor_lost_nodes[node_info.id] = nil
end

-- 会话关闭回调
function MonitorMgr:on_client_error(client, token, err)
    log_warn("[MonitorMgr][on_client_error] node name:%s, id:%s, token:%s,err:%s", service.id2nick(client.id), client.id, token, err)
    if client.id then
        self.monitor_lost_nodes[client.id] = self.monitor_nodes[token]
        self.monitor_nodes[token]          = nil
    end
end

-- 检测失活
function MonitorMgr:check_lost_node()
    for _, v in pairs(self.monitor_lost_nodes) do
        log_err("[MonitorMgr][check_lost_node] lost service:%s", v)
    end
end

--gm_page
function MonitorMgr:on_log_page(url, querys, request)
    if not log_page then
        local html_path = hive.import_file_dir("monitor/monitor_mgr.lua") .. "/log_page.html"
        log_page        = readfile(html_path)
        if not log_page then
            log_err("[MonitorMgr][on_log_page] load html faild:%s", html_path)
        end
    end
    return self.http_server:build_response(200, log_page)
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
    for _, client in self.rpc_server:iterator() do
        if sid == client.id then
            local ok, code, res = self.rpc_server:call(client, rpc, ...)
            if not ok then
                return { code = 1, msg = "call moniotor node failed!" }
            end
            return { code = code, msg = res }
        end
    end
    return { code = 1, msg = "target is nil" }
end

function MonitorMgr:send_by_sid(sid, rpc, ...)
    for _, client in self.rpc_server:iterator() do
        if sid == client.id then
            self.rpc_server:send(client, rpc, ...)
            return { code = 0, msg = "send target success" }
        end
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
    for token, client in self.rpc_server:iterator() do
        if service_id == 0 or service_id == client.service_id then
            self.rpc_server:send(client, rpc, ...)
        end
    end
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

hive.monitor_mgr = MonitorMgr()

return MonitorMgr
