--proxy_mgr.lua
import("driver/webhook.lua")
import("network/http_client.lua")

local webhook     = hive.get("webhook")
local event_mgr   = hive.get("event_mgr")
local http_client = hive.get("http_client")

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
function ProxyMgr:rpc_http_get(url, querys, headers, datas, timeout, debug)
    local ok, status, res = http_client:call_get(url, querys, headers, datas, timeout, debug)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_post(url, post_data, headers, querys, timeout, debug)
    local ok, status, res = http_client:call_post(url, post_data, headers, querys, timeout, debug)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_put(url, put_data, headers, querys, timeout, debug)
    local ok, status, res = http_client:call_put(url, put_data, headers, querys, timeout, debug)
    return ok and status or 404, res
end

function ProxyMgr:rpc_http_del(url, querys, headers, timeout, debug)
    local ok, status, res = http_client:call_del(url, querys, headers, timeout, debug)
    return ok and status or 404, res
end

hive.proxy_mgr = ProxyMgr()
