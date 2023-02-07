--monitor_agent.lua
local RpcClient     = import("network/rpc_client.lua")

local tunpack       = table.unpack
local signal_quit   = signal.quit
local env_addr      = environ.addr
local log_err       = logger.err
local log_warn      = logger.warn
local log_info      = logger.info
local check_success = hive.success
local check_failed  = hive.failed

local event_mgr     = hive.get("event_mgr")
local config_mgr    = hive.get("config_mgr")
local update_mgr    = hive.get("update_mgr")
local mem_monitor   = hive.get("mem_monitor")

local RPC_FAILED    = hive.enum("KernCode", "RPC_FAILED")

local MonitorAgent  = singleton()
local prop          = property(MonitorAgent)
prop:reader("client", nil)
function MonitorAgent:__init()
    --创建连接
    local ip, port = env_addr("HIVE_MONITOR_ADDR")
    self.client    = RpcClient(self, ip, port)
    --注册事件
    event_mgr:add_listener(self, "rpc_update_router_nodes")
    event_mgr:add_listener(self, "rpc_hive_quit")
    event_mgr:add_listener(self, "on_remote_message")
    event_mgr:add_listener(self, "rpc_reload")
    event_mgr:add_listener(self, "rpc_inject")
    event_mgr:add_listener(self, "rpc_set_server_status")
    event_mgr:add_listener(self, "rpc_set_log_level")
    event_mgr:add_listener(self, "rpc_config_reload")
    event_mgr:add_listener(self, "rpc_collect_gc")
    event_mgr:add_listener(self, "rpc_snapshot")
    event_mgr:add_listener(self, "rpc_count_lua_obj")
end

-- 连接关闭回调
function MonitorAgent:on_socket_error(client, token, err)
    log_info("[MonitorAgent][on_socket_error] disconnect monitor fail!:[%s:%s],err:%s", self.client.ip, self.client.port,err)
end

-- 连接成回调
function MonitorAgent:on_socket_connect(client)
    log_info("[MonitorAgent][on_socket_connect]: connect monitor success!:[%s:%s]", self.client.ip, self.client.port)
end

-- 请求服务
function MonitorAgent:service_request(api_name, data)
    local req           = {
        data    = data,
        id      = hive.id,
        index   = hive.index,
        service = hive.service_id,
    }
    local ok, code, res = self.client:call("rpc_monitor_post", api_name, req)
    if check_success(code, ok) then
        return tunpack(res)
    end
    return false
end

-- 更新路由
function MonitorAgent:rpc_update_router_nodes(router_nodes)
    local router_mgr = hive.get("router_mgr")
    if router_mgr then
        for id, node in pairs(router_nodes) do
            log_info("[MonitorAgent][rpc_update_router_nodes] %s,%s:%s", service.id2nick(id), node.host, node.port)
            router_mgr:add_router(id, node.host, node.port)
        end
    end
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
    hive.reload()
    hive.protobuf_mgr:reload()
    config_mgr:reload()

    event_mgr:notify_trigger("reload_config")
end

function MonitorAgent:rpc_config_reload()
    log_info("[MonitorAgent][rpc_config_reload]")
    config_mgr:reload()
    event_mgr:notify_trigger("reload_config")
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
    hive.service_status = status
    log_warn("[MonitorAgent][rpc_set_server_status] service_status:%s,:%s", hive.service_status, hive.name)
    event_mgr:notify_trigger("evt_set_server_status", hive.service_status)
end

function MonitorAgent:rpc_set_log_level(level)
    log_info("[MonitorAgent][rpc_set_log_level] level:%s", level)
    logger.filter(level)
end

hive.monitor = MonitorAgent()

return MonitorAgent
