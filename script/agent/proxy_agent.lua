--proxy_agent.lua
local sformat    = string.format
local tunpack    = table.unpack
local log_info   = logger.info

local event_mgr  = hive.get("event_mgr")
local scheduler  = hive.load("scheduler")

local ProxyAgent = singleton()
local prop       = property(ProxyAgent)
prop:reader("service_name", "proxy")          --地址
prop:reader("ignore_statistics", {})
prop:reader("statis_status", false)

function ProxyAgent:__init()
    if scheduler then
        --启动代理线程
        scheduler:startup("proxy", "worker.proxy")
        --日志上报
        if environ.status("HIVE_LOG_REPORT") then
            logger.add_monitor(self)
            log_info("[ProxyAgent:__init] open report log")
        end
        --开启统计
        self.statis_status = environ.status("HIVE_STATIS")
    end
    --添加忽略的rpc统计事件
    self:ignore_statis("rpc_heartbeat")
end

--日志分发
function ProxyAgent:dispatch_log(content, lvl_name, lvl)
    local title = sformat("[%s][%s]", hive.service_name, lvl_name)
    return self:send("rpc_dispatch_log", title, content, lvl)
end

function ProxyAgent:http_get(url, querys, headers)
    return self:call("rpc_http_get", url, querys, headers)
end

function ProxyAgent:http_post(url, post_data, headers, querys)
    return self:call("rpc_http_post", url, post_data, headers, querys)
end

function ProxyAgent:http_put(url, post_data, headers, querys)
    return self:call("rpc_http_put", url, post_data, headers, querys)
end

function ProxyAgent:http_del(url, querys, headers)
    return self:call("rpc_http_del", url, querys, headers)
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

function ProxyAgent:send(rpc, ...)
    if scheduler then
        return scheduler:send(self.service_name, rpc, ...)
    end
    event_mgr:notify_listener(rpc, ...)
end

function ProxyAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service_name, rpc, ...)
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    return tunpack(rpc_datas)
end

hive.proxy_agent = ProxyAgent()

return ProxyAgent
