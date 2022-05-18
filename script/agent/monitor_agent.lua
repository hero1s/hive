--monitor_agent.lua
local RpcClient      = import("network/rpc_client.lua")

local tunpack        = table.unpack
local signal_quit    = signal.quit
local env_addr       = environ.addr
local log_err        = logger.err
local log_warn       = logger.warn
local log_info       = logger.info
local check_success  = utility.check_success
local check_failed   = utility.check_failed

local event_mgr      = hive.get("event_mgr")
local timer_mgr      = hive.get("timer_mgr")
local thread_mgr     = hive.get("thread_mgr")
local config_mgr     = hive.get("config_mgr")

local RPC_FAILED     = hive.enum("KernCode", "RPC_FAILED")
local SECOND_MS      = hive.enum("PeriodTime", "SECOND_MS")
local RECONNECT_TIME = hive.enum("NetwkTime", "RECONNECT_TIME")
local HEARTBEAT_TIME = hive.enum("NetwkTime", "HEARTBEAT_TIME")

local MonitorAgent   = singleton()
local prop           = property(MonitorAgent)
prop:reader("client", nil)
prop:reader("next_connect_time", 0)
function MonitorAgent:__init()
    --创建连接
    local ip, port = env_addr("HIVE_MONITOR_ADDR")
    log_warn("monitor agent-----------%s,%s", ip, port)
    self.client = RpcClient(self, ip, port)
    --心跳定时器
    timer_mgr:loop(HEARTBEAT_TIME, function()
        self:on_timer()
    end)
    --注册事件
    event_mgr:add_listener(self, "on_hive_quit")
    event_mgr:add_listener(self, "on_remote_message")
    event_mgr:add_listener(self, "on_reload")
end

function MonitorAgent:on_timer()
    local now    = hive.now
    local client = self.client
    if not client:is_alive() then
        if now >= self.next_connect_time then
            self.next_connect_time = now + RECONNECT_TIME
            client:connect()
        end
    else
        if not client:check_lost(now) then
            client:heartbeat()
        end
    end
end

-- 连接关闭回调
function MonitorAgent:on_socket_error(client, token, err)
    -- 设置重连时间
    self.next_connect_time = hive.now
end

-- 连接成回调
function MonitorAgent:on_socket_connect(client)
    log_info("[MonitorAgent][on_socket_connect]: connect monitor success!")
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
    if ok and check_success(code) then
        return tunpack(res)
    end
    return false
end

-- 处理Monitor通知退出消息
function MonitorAgent:on_hive_quit(reason)
    -- 发个退出通知
    event_mgr:notify_trigger("on_hive_quit", reason)
    -- 关闭会话连接
    thread_mgr:fork(function()
        thread_mgr:sleep(SECOND_MS)
        self.client:close()
    end)
    timer_mgr:once(SECOND_MS, function()
        log_warn("[MonitorAgent][on_hive_quit]->service:%s", hive.name)
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
    if not ok or check_failed(code) then
        log_err("[MonitorAgent][on_remote_message] web_rpc faild: ok=%s, ec=%s", ok, code)
        return { code = ok and code or RPC_FAILED, msg = ok and "" or code }
    end
    return { code = 0, data = res }
end

function MonitorAgent:on_reload()
    log_info("[MonitorAgent][on_reload]")
    hive.reload()
    hive.protobuf_mgr:reload()
    config_mgr:reload()

    event_mgr:notify_trigger("reload_config", self)
end

hive.monitor = MonitorAgent()

return MonitorAgent
