-- router_mgr.lua
local lcodec           = require("lcodec")
local pairs            = pairs
local log_err          = logger.err
local log_info         = logger.info
local log_debug        = logger.debug
local mrandom          = math.random
local signal_quit      = signal.quit
local tunpack          = table.unpack
local sformat          = string.format
local sid2name         = service.id2name
local check_success    = hive.success
local jumphash         = lcodec.jumphash

local thread_mgr       = hive.get("thread_mgr")
local event_mgr        = hive.get("event_mgr")
local config_mgr       = hive.get("config_mgr")

local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")

local RouterMgr        = singleton()
local prop             = property(RouterMgr)
prop:accessor("master", nil)
prop:accessor("routers", {})
prop:accessor("candidates", {})
prop:accessor("ready_watchers", {})
prop:accessor("close_watchers", {})
prop:accessor("master_watchers", {})
function RouterMgr:__init()
    self:setup()
end

--初始化
function RouterMgr:setup()
    --router配置
    self:load_router()
    --router接口
    self:build_service()
    --注册事件
    event_mgr:add_listener(self, "rpc_router_update")
    event_mgr:add_listener(self, "rpc_service_close")
    event_mgr:add_listener(self, "rpc_service_ready")
    event_mgr:add_listener(self, "rpc_service_kickout")
    event_mgr:add_listener(self, "rpc_service_master")
end

--添加router
function RouterMgr:add_router(router_conf, index)
    log_debug("[RouterMgr][add_router] %s,%s", router_conf, index)
    local router_id = service.router_id(router_conf.host_id, index)
    if not self.routers[router_id] then
        local host              = router_conf.host
        --端口推导
        local port              = router_conf.port + (index - 1)
        local RpcClient         = import("network/rpc_client.lua")
        self.routers[router_id] = {
            addr      = host,
            router_id = router_id,
            client    = RpcClient(self, host, port)
        }
    end
end

--错误处理
function RouterMgr:on_socket_error(client, token, err)
    self:switch_master()
    log_err("[RouterMgr][on_socket_error] router lost %s:%s, err=%s", client.ip, client.port, err)
end

--连接成功
function RouterMgr:on_socket_connect(client, res)
    log_info("[RouterMgr][on_socket_connect] router %s:%s success!", client.ip, client.port)
    --switch master
    self:switch_master()
end

--切换主router
function RouterMgr:switch_master()
    self.candidates = {}
    for _, node in pairs(self.routers) do
        if node.client:is_alive() then
            self.candidates[#self.candidates + 1] = node
        end
    end
    local node = self:random_router()
    if node then
        self.master = node
        log_info("[RouterMgr][switch_master] switch router addr: %s", node.addr)
    end
end

--查找指定router
function RouterMgr:get_router(router_id)
    return self.routers[router_id]
end

--查找随机router
function RouterMgr:random_router()
    local count = #self.candidates
    if count > 0 then
        return self.candidates[mrandom(count)]
    end
end

--查找hash router
function RouterMgr:hash_router(hash_key)
    local count = #self.candidates
    if count > 0 then
        local index = jumphash(hash_key, count)
        local node  = self.candidates[index]
        if node == nil then
            log_err("[RouterMgr][hash_router] the hash node nil,hashkey:%s,index:%s", hash_key, index)
        end
        return node
    end
end

--通过router发送点对点消息
function RouterMgr:forward_client(router, method, rpc, session_id, ...)
    if router then
        return router.client:forward_socket(method, rpc, session_id, ...)
    end
    return false, "router not connected"
end

--通过router发送广播，并收集所有的结果
function RouterMgr:collect(service_id, rpc, ...)
    local collect_res          = {}
    local session_id           = thread_mgr:build_session_id()
    local ok, code, target_cnt = self:forward_client(self.master, "call_broadcast", rpc, session_id, service_id, rpc, ...)
    if check_success(code, ok) then
        while target_cnt > 0 do
            target_cnt              = target_cnt - 1
            local ok_c, code_c, res = thread_mgr:yield(session_id, "collect", RPC_CALL_TIMEOUT)
            if check_success(code_c, ok_c) then
                collect_res[#collect_res + 1] = res
            end
        end
    end
    return ok, code, collect_res
end

--通过router传递广播
function RouterMgr:broadcast(service_id, rpc, ...)
    return self:forward_client(self.master, "call_broadcast", rpc, 0, service_id, rpc, ...)
end

--发送给指定目标
function RouterMgr:call_target(target, rpc, ...)
    if target == hive.id then
        local res = event_mgr:notify_listener(rpc, ...)
        return tunpack(res)
    end
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:hash_router(target), "call_target", rpc, session_id, target, rpc, ...)
end

--发送给指定目标
function RouterMgr:send_target(target, rpc, ...)
    if target == hive.id then
        event_mgr:notify_listener(rpc, ...)
        return true
    end
    return self:forward_client(self:hash_router(target), "call_target", rpc, 0, target, rpc, ...)
end

--发送给指定目标
function RouterMgr:random_call(target, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:random_router(), "call_target", rpc, session_id, target, rpc, ...)
end

--发送给指定目标
function RouterMgr:random_send(target, rpc, ...)
    return self:forward_client(self:random_router(), "call_target", rpc, 0, target, rpc, ...)
end

--指定路由发送给指定目标
function RouterMgr:router_call(router_id, target, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:get_router(router_id), "call_target", rpc, session_id, target, rpc, ...)
end

--指定路由发送给指定目标
function RouterMgr:router_send(router_id, target, rpc, ...)
    return self:forward_client(self:get_router(router_id), "call_target", rpc, 0, target, rpc, ...)
end

--发送给指定service的hash
function RouterMgr:call_hash(service_id, hash_key, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:hash_router(hash_key), "call_hash", rpc, session_id, service_id, hash_key, rpc, ...)
end

--发送给指定service的hash
function RouterMgr:send_hash(service_id, hash_key, rpc, ...)
    return self:forward_client(self:hash_router(hash_key), "call_hash", rpc, 0, service_id, hash_key, rpc, ...)
end

--发送给指定service的random
function RouterMgr:call_random(service_id, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:hash_router(service_id), "call_random", rpc, session_id, service_id, rpc, ...)
end

--发送给指定service的random
function RouterMgr:send_random(service_id, rpc, ...)
    return self:forward_client(self:hash_router(service_id), "call_random", rpc, 0, service_id, rpc, ...)
end

--发送给指定service的master
function RouterMgr:call_master(service_id, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_client(self:hash_router(service_id), "call_master", rpc, session_id, service_id, rpc, ...)
end

--发送给指定service的master
function RouterMgr:send_master(service_id, rpc, ...)
    return self:forward_client(self:hash_router(service_id), "call_master", rpc, 0, service_id, rpc, ...)
end

--router加载
function RouterMgr:load_router()
    local router_db = config_mgr:init_table("router", "host")
    for _, router_conf in router_db:iterator() do
        for index = 1, router_conf.count do
            self:add_router(router_conf, index)
        end
    end
end

--生成针对服务的访问接口
function RouterMgr:build_service_method(service, service_id)
    local method_list = {
        ["call_%s_hash"]   = function(obj, hash_key, rpc, ...)
            return obj:call_hash(service_id, hash_key, rpc, ...)
        end,
        ["send_%s_hash"]   = function(obj, hash_key, rpc, ...)
            return obj:send_hash(service_id, hash_key, rpc, ...)
        end,
        ["call_%s_master"] = function(obj, rpc, ...)
            return obj:call_master(service_id, rpc, ...)
        end,
        ["send_%s_master"] = function(obj, rpc, ...)
            return obj:send_master(service_id, rpc, ...)
        end,
        ["call_%s_random"] = function(obj, rpc, ...)
            return obj:call_random(service_id, rpc, ...)
        end,
        ["send_%s_random"] = function(obj, rpc, ...)
            return obj:send_random(service_id, rpc, ...)
        end,
        ["send_%s_all"]    = function(obj, rpc, ...)
            return obj:broadcast(service_id, rpc, ...)
        end,
        ["collect_%s"]     = function(obj, rpc, ...)
            return obj:collect(service_id, rpc, ...)
        end,
    }
    for fmt_key, handler in pairs(method_list) do
        local method = sformat(fmt_key, service)
        if not RouterMgr[method] then
            RouterMgr[method] = handler
        end
    end
end


--生成针对服务的访问接口
function RouterMgr:build_service()
    local services = service.services()
    for service, service_id in pairs(services) do
        self:build_service_method(service, service_id)
    end
end

--监听服务断开
function RouterMgr:watch_service_close(listener, service_name)
    if not self.close_watchers[service_name] then
        self.close_watchers[service_name] = {}
    end
    self.close_watchers[service_name][listener] = true
end

--监听服务注册
function RouterMgr:watch_service_ready(listener, service_name)
    if not self.ready_watchers[service_name] then
        self.ready_watchers[service_name] = {}
    end
    self.ready_watchers[service_name][listener] = true
end

--监听服务切换master
function RouterMgr:watch_service_master(listener)
    if not self.master_watchers then
        self.master_watchers = {}
    end
    self.master_watchers[listener] = true
end

--业务事件响应
-------------------------------------------------------------------------------
-- 刷新router配置
function RouterMgr:rpc_router_update()
    self:load_router()
end

function RouterMgr:is_master_router(router_id)
    return self.master and self.master.router_id == router_id
end

--服务器关闭
function RouterMgr:rpc_service_close(id, router_id)
    if self:is_master_router(router_id) then
        local server_name  = sid2name(id)
        local listener_set = self.close_watchers[server_name]
        for listener in pairs(listener_set or {}) do
            listener:on_service_close(id, server_name)
        end
    end
end

--服务器注册
function RouterMgr:rpc_service_ready(id, router_id)
    if self:is_master_router(router_id) then
        local server_name  = sid2name(id)
        local listener_set = self.ready_watchers[server_name]
        for listener in pairs(listener_set or {}) do
            listener:on_service_ready(id, server_name)
        end
    end
end

--服务器切换master
function RouterMgr:rpc_service_master(id, router_id)
    if self:is_master_router(router_id) then
        for listener in pairs(self.master_watchers or {}) do
            listener:on_service_master(id)
        end
    end
end

--服务被踢下线
function RouterMgr:rpc_service_kickout(router_id, reason)
    log_err("[RouterMgr][rpc_service_kickout] reason:%s router_id:%s", reason, router_id)
    signal_quit()
end

hive.router_mgr = RouterMgr()

return RouterMgr
