--proxy_mgr.lua
import("driver/webhook.lua")
import("driver/graylog.lua")
import("network/http_client.lua")

local InfluxDB    = import("driver/influx.lua")

local env_get     = environ.get
local env_addr    = environ.addr

local webhook     = hive.get("webhook")
local graylog     = hive.get("graylog")
local event_mgr   = hive.get("event_mgr")
local http_client = hive.get("http_client")
local thread_mgr  = hive.get("thread_mgr")
local ProxyMgr    = singleton()
local prop        = property(ProxyMgr)
prop:reader("influx", nil)              --influx
function ProxyMgr:__init()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_dispatch_log")
    -- 通用http请求
    event_mgr:add_listener(self, "rpc_http_post")
    event_mgr:add_listener(self, "rpc_http_get")
    event_mgr:add_listener(self, "rpc_http_put")
    event_mgr:add_listener(self, "rpc_http_del")
    -- statis
    event_mgr:add_listener(self, "rpc_write_statis")
    self:setup()
end

function ProxyMgr:setup()
    --初始化参数
    local org      = env_get("HIVE_INFLUX_ORG")
    local token    = env_get("HIVE_INFLUX_TOKEN")
    local bucket   = env_get("HIVE_INFLUX_BUCKET")
    local ip, port = env_addr("HIVE_INFLUX_ADDR")
    if ip and port then
        self.influx = InfluxDB(ip, port, org, bucket, token)
    end
end

--日志上报
function ProxyMgr:rpc_dispatch_log(title, content, lvl)
    thread_mgr:fork(function()
        webhook:notify(title, content, lvl)
    end)
    thread_mgr:fork(function()
        graylog:write(content, lvl)
    end)
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

function ProxyMgr:rpc_write_statis(statis)
    if self.influx and next(statis) then
        thread_mgr:fork(function()
            self.influx:batch(statis)
        end)
    end
end

hive.proxy_mgr = ProxyMgr()
