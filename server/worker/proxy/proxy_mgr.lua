--proxy_mgr.lua
import("driver/webhook.lua")
import("network/http_client.lua")

local webhook     = hive.get("webhook")
local event_mgr   = hive.get("event_mgr")
local http_client = hive.get("http_client")
local log_debug   = logger.debug

local ProxyMgr    = singleton()

function ProxyMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_fire_webhook")
    -- 通用http请求
    event_mgr:add_listener(self, "rpc_http_post")
    event_mgr:add_listener(self, "rpc_http_get")
    event_mgr:add_listener(self, "rpc_http_put")
    event_mgr:add_listener(self, "rpc_http_del")

    self:setup()
end

function ProxyMgr:setup()

end

--日志上报
function ProxyMgr:rpc_fire_webhook(title, content)
    webhook:notify(title, content)
end

--通用http请求
function ProxyMgr:rpc_http_get(url, querys, headers, datas, timeout)
    local ok, status, res = http_client:call_get(url, querys, headers, datas, timeout)
    if not ok or status ~= 200 then
        log_debug("[ProxyMgr][rpc_http_get] failed:%s,%s,%s,%s", url, ok, status, res)
    end
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_post(url, post_data, headers, querys, timeout)
    local ok, status, res = http_client:call_post(url, post_data, headers, querys, timeout)
    if not ok or status ~= 200 then
        log_debug("[ProxyMgr][rpc_http_post] failed:%s,%s,%s,%s", url, ok, status, res)
    end
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_put(url, put_data, headers, querys, timeout)
    local ok, status, res = http_client:call_put(url, put_data, headers, querys, timeout)
    if not ok or status ~= 200 then
        log_debug("[ProxyMgr][rpc_http_put] failed:%s,%s,%s,%s", url, ok, status, res)
    end
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_del(url, querys, headers, timeout)
    local ok, status, res = http_client:call_del(url, querys, headers, timeout)
    if not ok or status ~= 200 then
        log_debug("[ProxyMgr][rpc_http_del] failed:%s,%s,%s,%s", url, ok, status, res)
    end
    return ok and status or 404, res
end

hive.proxy_mgr = ProxyMgr()
