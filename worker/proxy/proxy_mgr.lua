--proxy_mgr.lua
import("driver/webhook.lua")
import("driver/graylog.lua")
import("network/http_client.lua")

local webhook       = hive.get("webhook")
local graylog       = hive.get("graylog")
local event_mgr     = hive.get("event_mgr")
local http_client   = hive.get("http_client")

local ProxyMgr = singleton()

function ProxyMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_dispatch_log")
    -- 通用http请求
    event_mgr:add_listener(self, "rpc_http_post")
    event_mgr:add_listener(self, "rpc_http_get")
    event_mgr:add_listener(self, "rpc_http_put")
    event_mgr:add_listener(self, "rpc_http_del")
end

--日志上报
function ProxyMgr:rpc_dispatch_log(title, content, lvl)
    webhook:notify(title, content, lvl)
    graylog:write(content, lvl)
end

--通用http请求
function ProxyMgr:rpc_http_get(url, querys, headers)
    local ok, status, res = http_client:call_get(url, querys, headers)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_post(url, post_data, headers, querys)
    local ok, status, res = http_client:call_post(url, post_data, headers, querys)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_put(url, put_data, headers, querys)
    local ok, status, res = http_client:call_put(url, put_data, headers, querys)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_del(url, querys, headers)
    local ok, status, res = http_client:call_del(url, querys, headers)
    return ok and status or 404, res
end

hive.proxy_mgr = ProxyMgr()
