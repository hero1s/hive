--monitor_agent.lua
local RpcClient     = import("network/rpc_client.lua")

local tunpack       = table.unpack
local tinsert       = table.insert
local env_addr      = environ.addr
local log_err       = logger.err
local log_warn      = logger.warn
local log_info      = logger.info
local log_debug     = logger.debug
local check_failed  = hive.failed
local smake_id      = service.make_id

local event_mgr     = hive.get("event_mgr")
local gc_mgr        = hive.get("gc_mgr")
local mem_monitor   = hive.get("mem_monitor")
local thread_mgr    = hive.get("thread_mgr")

local RPC_FAILED    = hive.enum("KernCode", "RPC_FAILED")
local ServiceStatus = enum("ServiceStatus")

local MonitorAgent  = singleton()
local prop          = property(MonitorAgent)
prop:reader("client", nil)
prop:reader("ready_watchers", {})
prop:reader("close_watchers", {})
prop:reader("services", {})

function MonitorAgent:__init()
    --创建连接
    local ip, port = env_addr("HIVE_MONITOR_ADDR")
    self.client    = RpcClient(self, ip, port)
    --注册事件
    event_mgr:add_vote(self, "vote_stop_service")
    event_mgr:add_listener(self, "rpc_service_changed")
    event_mgr:add_listener(self, "on_remote_message")
    event_mgr:add_listener(self, "rpc_reload")
    event_mgr:add_listener(self, "rpc_inject")
    event_mgr:add_listener(self, "rpc_set_env")
    event_mgr:add_listener(self, "rpc_set_server_status")
    event_mgr:add_listener(self, "rpc_hive_quit")
    event_mgr:add_listener(self, "rpc_set_log_level")
    event_mgr:add_listener(self, "rpc_collect_gc")
    event_mgr:add_listener(self, "rpc_snapshot")
    event_mgr:add_listener(self, "rpc_count_lua_obj")

    event_mgr:add_trigger(self, "on_router_connected")
end

--检测是否可以自动退出
function MonitorAgent:vote_stop_service()
    if not hive.is_ready() then
        return true
    end
    for _, name in ipairs(hive.pre_services or {}) do
        if self:exist_service(name) then
            log_warn("[MonitorAgent][vote_stop_service] pre service [%s] has runing,wait next check", name)
            return false
        end
        log_debug("[MonitorAgent][vote_stop_service] pre service [%s] has stop", name)
    end
    return true
end

function MonitorAgent:on_router_connected(is_ready)
    --self.client:register()
end

--监听服务断开
function MonitorAgent:watch_service_close(listener, service_name)
    if not self.close_watchers[service_name] then
        self.close_watchers[service_name] = {}
    end
    self.close_watchers[service_name][listener] = true
end

--监听服务注册
function MonitorAgent:watch_service_ready(listener, service_name)
    if not self.ready_watchers[service_name] then
        self.ready_watchers[service_name] = {}
    end
    self.ready_watchers[service_name][listener] = true
end

function MonitorAgent:watch_services()
    local services = {}
    for service_name, _ in pairs(self.ready_watchers) do
        tinsert(services, service_name)
    end
    for service_name, _ in pairs(self.close_watchers) do
        tinsert(services, service_name)
    end
    return services
end

function MonitorAgent:is_watch_service(service_name)
    if self.ready_watchers[service_name] or self.close_watchers[service_name] then
        return true
    end
    for _, name in ipairs(hive.pre_services or {}) do
        if name == service_name then
            return true
        end
    end
    return false
end

function MonitorAgent:exist_service(service_name, index)
    local services = self.services[service_name]
    if services then
        if index then
            local sid = smake_id(service_name, index)
            return services[sid] and true or false
        end
        return next(services) and true or false
    end
    return false
end

-- 连接关闭回调
function MonitorAgent:on_socket_error(client, token, err)
    log_info("[MonitorAgent][on_socket_error] disconnect monitor fail!:[%s:%s],err:%s", self.client.ip, self.client.port, err)
end

-- 连接成回调
function MonitorAgent:on_socket_connect(client)
    log_info("[MonitorAgent][on_socket_connect]: connect monitor success!:[%s:%s]", self.client.ip, self.client.port)
end

function MonitorAgent:notify_service_event(listener_set, service_name, id, info, is_ready)
    for listener in pairs(listener_set or {}) do
        if id ~= hive.id then
            thread_mgr:fork(function()
                if is_ready then
                    listener:on_service_ready(id, service_name, info)
                else
                    listener:on_service_close(id, service_name, info)
                end
            end)
        end
    end
end

--服务改变
function MonitorAgent:rpc_service_changed(service_name, readys, closes)
    if not self:is_watch_service(service_name) then
        return
    end
    log_debug("[MonitorAgent][rpc_service_changed] %s,%s,%s", service_name, readys, closes)
    for id, info in pairs(readys) do
        if not self.services[service_name] then
            self.services[service_name] = {}
        end
        if not self.services[service_name][id] then
            self.services[service_name][id] = true
            self:notify_service_event(self.ready_watchers[service_name], service_name, id, info, true)
        end
        --todo 后续优化多次通知的问题 toney
    end
    for id, _ in pairs(closes) do
        if self.services[service_name] then
            self.services[service_name][id] = nil
        end
        self:notify_service_event(self.close_watchers[service_name], service_name, id, {}, false)
    end
end

--执行远程rpc消息
function MonitorAgent:on_remote_message(data, message)
    if not message then
        return { code = RPC_FAILED, msg = "message is nil !" }
    end
    local ok, code, res = tunpack(event_mgr:notify_listener(message, data))
    if check_failed(code, ok) then
        log_err("[MonitorAgent][on_remote_message] web_rpc faild: ok=%s, ec=%s", ok, code)
        return { code = ok and code or RPC_FAILED, msg = ok and "" or code }
    end
    return { code = 0, data = res }
end

function MonitorAgent:rpc_reload()
    log_info("[MonitorAgent][rpc_reload]")
    signal.hotfix()
    --hive.protobuf_mgr:reload() todo 暂时不热更协议 toney
end

function MonitorAgent:rpc_collect_gc()
    gc_mgr:collect_gc()
end

function MonitorAgent:rpc_snapshot(snap)
    if snap == 0 then
        return mem_monitor:start()
    else
        return mem_monitor:stop(true)
    end
end

function MonitorAgent:rpc_count_lua_obj(less_num)
    local obj_counts = show_class_track(less_num)
    log_warn("rpc_count_lua_obj:%s", obj_counts)
    return { objs = obj_counts, lua_mem = gc_mgr:lua_mem_size(), mem = gc_mgr:mem_size() }
end

function MonitorAgent:rpc_inject(code_string)
    local func = load(code_string)
    return func()
end

function MonitorAgent:rpc_set_env(key, value)
    local old = environ.get(key)
    environ.set(key, value)
    log_debug("[MonitorAgent][rpc_set_env] %s:%s,old:%s --> new:%s", key, value, old, environ.get(key))
    event_mgr:notify_trigger("evt_change_env", key)
end

function MonitorAgent:rpc_set_server_status(status)
    if hive.service_status == ServiceStatus.STOP then
        log_err("[MonitorAgent][rpc_set_server_status] change status irreversible: %s --> %s ", status, hive.service_status)
        return
    end
    hive.change_service_status(status)
end

function MonitorAgent:rpc_hive_quit(reason)
    if hive.safe_stop and hive.service_status ~= ServiceStatus.STOP then
        hive.change_service_status(ServiceStatus.STOP)
    end
end

function MonitorAgent:rpc_set_log_level(level)
    log_info("[MonitorAgent][rpc_set_log_level] level:%s", level)
    logger.filter(level)
end

hive.monitor = MonitorAgent()

return MonitorAgent
