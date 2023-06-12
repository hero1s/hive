--proxy_agent.lua
local sformat     = string.format
local tunpack     = table.unpack
local log_warn    = logger.warn
local send_worker = hive.send_worker
local call_worker = hive.call_worker

local TITLE      = hive.title
local event_mgr   = hive.get("event_mgr")
local scheduler   = hive.load("scheduler")

local ProxyAgent  = singleton()
local prop        = property(ProxyAgent)
prop:reader("service", "proxy")
prop:reader("ignore_statistics", {})
prop:reader("statis_status", false)

function ProxyAgent:__init()
    if scheduler then
        --启动代理线程
        scheduler:startup(self.service, "worker.proxy")
        --日志上报
        local wlvl = environ.number("HIVE_WEBHOOK_LVL")
        if wlvl then
            --添加webhook功能
            logger.add_monitor(self, wlvl)
        end
        --开启统计
        if environ.status("HIVE_STATIS") then
            self.statis_status = true
            log_warn("[ProxyAgent:__init] open statis !!!,it will degrade performance")
        end
        event_mgr:add_trigger(self, "evt_change_service_status")
    end
    --添加忽略的rpc统计事件
    self:ignore_statis("rpc_heartbeat")
    self:ignore_statis("on_heartbeat")
end

--日志分发
function ProxyAgent:dispatch_log(content, lvl_name)
    local title = sformat("[%s][%s]", hive.name, lvl_name)
    return self:send("rpc_fire_webhook", title, content)
end

function ProxyAgent:http_get(url, querys, headers, datas, timeout, debug)
    return self:call("rpc_http_get", url, querys, headers, datas, timeout, debug)
end

function ProxyAgent:http_post(url, post_data, headers, querys, timeout, debug)
    return self:call("rpc_http_post", url, post_data, headers, querys, timeout, debug)
end

function ProxyAgent:http_put(url, post_data, headers, querys, timeout, debug)
    return self:call("rpc_http_put", url, post_data, headers, querys, timeout, debug)
end

function ProxyAgent:http_del(url, querys, headers, timeout, debug)
    return self:call("rpc_http_del", url, querys, headers, timeout, debug)
end

function ProxyAgent:ignore_statis(name)
    self.ignore_statistics[name] = true
end

function ProxyAgent:statistics(event, name, ...)
    if not self.statis_status then
        return
    end
    if self.ignore_statistics[name] then
        return
    end
    self:send(event, name, ...)
end

function ProxyAgent:evt_change_service_status(service_status)
    local monitor = hive.load("monitor")
    if monitor then
        self:call("rpc_watch_service", monitor:watch_services(), hive.pre_services)
        self:register_nacos(hive.node_info)
    end
end

function ProxyAgent:register_nacos(node)
    return self:call("rpc_register_nacos", node)
end

function ProxyAgent:unregister_nacos()
    return self:call("rpc_unregister_nacos")
end

function ProxyAgent:send(rpc, ...)
    if scheduler then
        return scheduler:send(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return send_worker(self.service, rpc, ...)
    end
    event_mgr:notify_listener(rpc, ...)
end

function ProxyAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return call_worker(self.service, rpc, ...)
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    return tunpack(rpc_datas)
end

hive.proxy_agent = ProxyAgent()

return ProxyAgent
