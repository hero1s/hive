--proxy_agent.lua
local sformat    = string.format
local log_info   = logger.info
local log_err    = logger.err
local scheduler  = hive.get("scheduler")

local ProxyAgent = singleton()
local prop       = property(ProxyAgent)
prop:reader("service_name", "proxy")          --地址

function ProxyAgent:__init()
    --启动代理线程
    scheduler:startup(self.service_name, "proxy")
    --日志上报
    if environ.status("HIVE_LOG_REPORT") then
        logger.add_monitor(self)
        log_info("[ProxyAgent][__init] open hive log report!!!")
    end
end

--日志分发
function ProxyAgent:dispatch_log(content, lvl_name, lvl)
    local title = sformat("[%s][%s]", hive.service_name, lvl_name)
    scheduler:send(self.service_name, "rpc_dispatch_log", title, content, lvl)
end

function ProxyAgent:get(url, querys, headers)
    local ok, code, res = scheduler:call(self.service_name, "rpc_http_get", url, querys, headers)
    if not ok or 200 ~= code then
        log_err("[ProxyAgent][get] call faild:url=%s, ok=%s,code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

function ProxyAgent:post(url, post_data, headers, querys)
    local ok, code, res = scheduler:call(self.service_name, "rpc_http_post", url, post_data, headers, querys)
    if not ok or 200 ~= code then
        log_err("[ProxyAgent][post] call faild:url=%s, ok=%s, code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

function ProxyAgent:put(url, post_data, headers, querys)
    local ok, code, res = scheduler:call(self.service_name, "rpc_http_put", url, post_data, headers, querys)
    if not ok or 200 ~= code then
        log_err("[ProxyAgent][put] call faild:url=%s, ok=%s, code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

function ProxyAgent:del(url, querys, headers)
    local ok, code, res = scheduler:call(self.service_name, "rpc_http_del", url, querys, headers)
    if not ok or 200 ~= code then
        log_err("[ProxyAgent][del] call faild:url=%s, ok=%s,code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

hive.proxy_agent = ProxyAgent()

return ProxyAgent
