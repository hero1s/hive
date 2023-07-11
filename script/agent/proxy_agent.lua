local sformat    = string.format
local log_warn   = logger.warn
local scheduler  = hive.load("scheduler")

local thread     = import("feature/worker_agent.lua")
local ProxyAgent = singleton(thread)
local prop       = property(ProxyAgent)
prop:reader("ignore_statistics", {})
prop:reader("statis_status", false)

function ProxyAgent:__init()
    if scheduler then
        self:startup("proxy", "worker.proxy")
        --开启统计
        if environ.status("HIVE_STATIS") then
            self.statis_status = true
            log_warn("[ProxyAgent:__init] open statis !!!,it will degrade performance")
        end
    end
    --添加忽略的rpc统计事件
    self:ignore_statis("rpc_heartbeat")
    self:ignore_statis("on_heartbeat")
    --日志上报
    local wlvl = environ.number("HIVE_WEBHOOK_LVL")
    if wlvl then
        --添加webhook功能
        logger.add_monitor(self, wlvl)
    end
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

hive.proxy_agent = ProxyAgent()

return ProxyAgent
