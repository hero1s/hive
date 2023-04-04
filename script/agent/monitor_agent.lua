--monitor_agent.lua
local RpcClient    = import("network/rpc_client.lua")

local tunpack      = table.unpack
local tinsert      = table.insert
local signal_quit  = signal.quit
local env_addr     = environ.addr
local log_err      = logger.err
local log_warn     = logger.warn
local log_info     = logger.info
local log_debug    = logger.debug
local check_failed = hive.failed

local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")
local update_mgr   = hive.get("update_mgr")
local mem_monitor  = hive.get("mem_monitor")
local thread_mgr   = hive.get("thread_mgr")

local RPC_FAILED   = hive.enum("KernCode", "RPC_FAILED")

local MonitorAgent = singleton()
local prop         = property(MonitorAgent)
prop:reader("client", nil)
prop:reader("ready_watchers", {})
prop:reader("close_watchers", {})

function MonitorAgent:__init()
    --创建连接
    local ip, port = env_addr("HIVE_MONITOR_ADDR")
    self.client    = RpcClient(self, ip, port)
    --注册事件
    event_mgr:add_listener(self, "rpc_service_changed")
    event_mgr:add_listener(self, "rpc_hive_quit")
    event_mgr:add_listener(self, "on_remote_message")
    event_mgr:add_listener(self, "rpc_reload")
    event_mgr:add_listener(self, "rpc_inject")
    event_mgr:add_listener(self, "rpc_set_server_status")
    event_mgr:add_listener(self, "rpc_set_log_level")
    event_mgr:add_listener(self, "rpc_collect_gc")
    event_mgr:add_listener(self, "rpc_snapshot")
    event_mgr:add_listener(self, "rpc_count_lua_obj")
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

-- 连接关闭回调
function MonitorAgent:on_socket_error(client, token, err)
    log_info("[MonitorAgent][on_socket_error] disconnect monitor fail!:[%s:%s],err:%s", self.client.ip, self.client.port, err)
end

-- 连接成回调
function MonitorAgent:on_socket_connect(client)
    log_info("[MonitorAgent][on_socket_connect]: connect monitor success!:[%s:%s]", self.client.ip, self.client.port)
end

function MonitorAgent:notify_service_event(listener_set, service_name, services, is_ready)
    for listener in pairs(listener_set or {}) do
        for id, info in pairs(services) do
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
end

--服务改变
function MonitorAgent:rpc_service_changed(service_name, readys, closes)
    log_debug("[MonitorAgent][rpc_service_changed] %s,%s,%s", service_name, readys, closes)
    self:notify_service_event(self.ready_watchers[service_name], service_name, readys, true)
    self:notify_service_event(self.ready_watchers["*"], service_name, readys, true)

    self:notify_service_event(self.close_watchers[service_name], service_name, closes, false)
    self:notify_service_event(self.close_watchers["*"], service_name, closes, false)
end

-- 处理Monitor通知退出消息
function MonitorAgent:rpc_hive_quit(reason)
    -- 发个退出通知
    event_mgr:notify_trigger("evt_hive_quit", reason)
    update_mgr:attach_next(function()
        log_warn("[MonitorAgent][on_hive_quit]->service:%s,reason:%s", hive.name, reason)
        signal_quit()
    end)
    return { code = 0 }
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
    if hive.reload() > 0 then
        hive.protobuf_mgr:reload()
        config_mgr:reload(true)
    end
end

function MonitorAgent:rpc_collect_gc()
    update_mgr:collect_gc()
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
    return obj_counts
end

function MonitorAgent:rpc_inject(code_string)
    local func = load(code_string)
    return func()
end

function MonitorAgent:rpc_set_server_status(status)
    hive.change_service_status(status)
end

function MonitorAgent:rpc_set_log_level(level)
    log_info("[MonitorAgent][rpc_set_log_level] level:%s", level)
    logger.filter(level)
end

hive.monitor = MonitorAgent()

return MonitorAgent
