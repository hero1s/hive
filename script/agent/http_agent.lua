--http_agent.lua
import("network/http_client.lua")

local log_info    = logger.info
local log_err     = logger.err
local tsize       = table_ext.size

local router_mgr  = hive.get("router_mgr")
local http_client = hive.get("http_client")

local HttpAgent   = singleton()
local prop        = property(HttpAgent)
prop:accessor("proxy", false)
prop:accessor("pids", {})
function HttpAgent:__init()
    router_mgr:watch_service_ready(self, "proxy")
    router_mgr:watch_service_close(self, "proxy")
end

-- proxy服务已经ready
function HttpAgent:on_service_ready(id, service_name)
    log_info("[HttpAgent][on_service_ready]->id:%s, service_name:%s", id, service_name)
    self.proxy    = true
    self.pids[id] = id
end

function HttpAgent:on_service_close(id, service_name)
    log_info("[HttpAgent][on_service_close]->id:%s, service_name:%s", id, service_name)
    self.pids[id] = nil
    if tsize(self.pids) == 0 then
        self.proxy = false
    end
end

function HttpAgent:get(url, querys, headers)
    local ok, code, res
    if self.proxy then
        ok, code, res = router_mgr:call_proxy_random("rpc_http_get", url, querys, headers)
    else
        ok, code, res = http_client:call_get(url, querys, headers)
    end
    if not ok or 200 ~= code then
        log_err("[HttpAgent][get] call faild:url=%s, ok=%s,code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

function HttpAgent:post(url, post_data, headers, querys)
    local ok, code, res
    if self.proxy then
        ok, code, res = router_mgr:call_proxy_random("rpc_http_post", url, post_data, headers, querys)
    else
        ok, code, res = http_client:call_post(url, post_data, headers, querys)
    end
    if not ok or 200 ~= code then
        log_err("[HttpAgent][post] call faild:url=%s, ok=%s, code=%s,res=%s", url, ok, code, res)
    end
    return ok, code, res
end

------------------------------------------------------------------
hive.http_agent = HttpAgent()

return HttpAgent
