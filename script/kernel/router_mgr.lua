-- router_mgr.lua
local jumphash         = codec.jumphash
local pairs            = pairs
local log_err          = logger.err
local log_info         = logger.info
local signal_quit      = signal.quit
local tsort            = table.sort
local tunpack          = table.unpack
local sformat          = string.format
local id2nick          = service.id2nick
local id2group         = service.id2group
local check_success    = hive.success
local mrandom          = math_ext.random
local time_str         = datetime_ext.time_str

local monitor          = hive.get("monitor")
local thread_mgr       = hive.get("thread_mgr")
local event_mgr        = hive.get("event_mgr")

local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")
local RPC_UNREACHABLE  = hive.enum("KernCode", "RPC_UNREACHABLE")
local NOT_ROUTER       = hive.enum("KernCode", "NOT_ROUTER")
local SECOND_MS        = hive.enum("PeriodTime", "SECOND_MS")

local RouterMgr        = singleton()
local prop             = property(RouterMgr)
prop:accessor("routers", {})
prop:accessor("candidates", {})
function RouterMgr:__init()
    self:setup()
end

--初始化
function RouterMgr:setup()
    --router接口
    self:build_service()
    --监听路由信息
    monitor:watch_service_ready(self, "router")
    monitor:watch_service_close(self, "router")
    --注册事件
    event_mgr:add_listener(self, "rpc_service_kickout")
    event_mgr:add_listener(self, "on_forward_error")
    event_mgr:add_listener(self, "reply_forward_error")
    event_mgr:add_listener(self, "on_heartbeat")
end

--服务关闭
function RouterMgr:on_service_close(id, name)
    log_info("[RouterMgr][on_service_close] node: {}", id2nick(id))
end

--服务上线
function RouterMgr:on_service_ready(id, name, info)
    log_info("[RouterMgr][on_service_ready] node: {}, info: {}", id2nick(id), info)
    self:add_router(info.id, info.ip, info.port)
end

--添加router
function RouterMgr:add_router(router_id, host, port)
    if router_id == hive.id then
        return
    end
    local group = id2group(router_id)
    --不同组的只连router服
    if group ~= hive.group and hive.service_name ~= "router" then
        return
    end
    local router = self.routers[router_id]
    if router then
        if router.ip ~= host or router.port ~= port then
            router:close()
            self.routers[router_id] = nil
            log_err("[RouterMgr][add_router] replace new router:{},{},{}", id2nick(router_id), host, port)
        else
            return
        end
    end
    log_info("[RouterMgr][add_router] {} --> {},{}:{}", hive.name, id2nick(router_id), host, port)
    local RpcClient         = import("network/rpc_client.lua")
    self.routers[router_id] = RpcClient(self, host, port, router_id)
end

--错误处理
function RouterMgr:on_socket_error(client, token, err)
    self:check_router()
    if hive.status_run() then
        log_err("[RouterMgr][on_socket_error] router lost {}:{},token:{}, err={}", client.ip, client.port, token, err)
    else
        log_info("[RouterMgr][on_socket_error] router lost {}:{},token:{}, err={}", client.ip, client.port, token, err)
    end
end

--连接成功
function RouterMgr:on_socket_connect(client, res)
    log_info("[RouterMgr][on_socket_connect] router {}:{} success!", client.ip, client.port)
    self:check_router()
    client:register()
end

function RouterMgr:check_router()
    local old_ready  = self:is_ready()
    local candidates = {}
    for _, client in pairs(self.routers) do
        if client:is_alive() then
            candidates[#candidates + 1] = client
        end
    end
    tsort(candidates, function(a, b)
        return a.id < b.id
    end)
    self.candidates = candidates
    if old_ready ~= self:is_ready() then
        hive.change_service_status(hive.service_status)
        event_mgr:notify_trigger("on_router_connected", self:is_ready())
    end
end

function RouterMgr:is_ready()
    return #self.candidates > 0
end

--查找hash router
function RouterMgr:hash_router(hash_key)
    local count = #self.candidates
    if count > 0 then
        local index = jumphash(hash_key, count)
        local node  = self.candidates[index]
        if node == nil then
            log_err("[RouterMgr][hash_router] the hash node nil,hashkey:{},index:{}", hash_key, index)
        end
        return node
    end
end

--通过router发送点对点消息
function RouterMgr:forward_target(hash_key, method, rpc, session_id, ...)
    local router = self:hash_router(hash_key)
    if router then
        return router:forward_socket(method, rpc, session_id, ...)
    end
    return false, NOT_ROUTER
end

--通过router发送广播，并收集所有的结果
function RouterMgr:collect(service_id, rpc, ...)
    local collect_res = {}
    if service_id == hive.service_id then
        local ok, code, res = self:call_target(hive.id, rpc, ...)
        if check_success(code, ok) then
            collect_res[#collect_res + 1] = res
        end
    end
    local session_id           = thread_mgr:build_session_id()
    local ok, code, target_cnt = self:forward_target(session_id, "call_broadcast", rpc, session_id, service_id, rpc, ...)
    if check_success(code, ok) then
        while target_cnt > 0 do
            target_cnt              = target_cnt - 1
            local ok_c, code_c, res = thread_mgr:yield(session_id, rpc, RPC_CALL_TIMEOUT)
            if check_success(code_c, ok_c) then
                collect_res[#collect_res + 1] = res
            end
        end
    end
    return ok, code, collect_res
end

--通过router传递广播
function RouterMgr:broadcast(service_id, rpc, ...)
    return self:forward_target(service_id + hive.id, "call_broadcast", rpc, 0, service_id, rpc, ...)
end

--发送给指定目标
function RouterMgr:call_target(target, rpc, ...)
    if target == hive.id then
        local res = event_mgr:notify_listener(rpc, ...)
        return tunpack(res)
    end
    local session_id = thread_mgr:build_session_id()
    return self:forward_target(target + hive.id, "call_target", rpc, session_id, target, rpc, ...)
end

--发送给指定目标
function RouterMgr:send_target(target, rpc, ...)
    if target == hive.id then
        event_mgr:notify_listener(rpc, ...)
        return true
    end
    return self:forward_target(target + hive.id, "call_target", rpc, 0, target, rpc, ...)
end

--发送给路由
function RouterMgr:call_router(hash_key, rpc, ...)
    local router = self:hash_router(hash_key)
    if router then
        return router:call(rpc, ...)
    end
    return false, NOT_ROUTER
end

--发送给路由
function RouterMgr:send_router(hash_key, rpc, ...)
    local router = self:hash_router(hash_key)
    if router then
        return router:send(rpc, ...)
    end
end

function RouterMgr:broadcast_router(rpc, ...)
    for _, node in pairs(self.candidates) do
        node:send(rpc, ...)
    end
end

--发送给指定service的hash
function RouterMgr:call_hash(service_id, hash_key, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_target(hash_key, "call_hash", rpc, session_id, service_id, hash_key, rpc, ...)
end

--发送给指定service的hash
function RouterMgr:send_hash(service_id, hash_key, rpc, ...)
    return self:forward_target(hash_key, "call_hash", rpc, 0, service_id, hash_key, rpc, ...)
end

--发送给指定service的master
function RouterMgr:call_master(service_id, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_target(service_id + hive.id, "call_master", rpc, session_id, service_id, rpc, ...)
end

--发送给指定service的master
function RouterMgr:send_master(service_id, rpc, ...)
    return self:forward_target(service_id + hive.id, "call_master", rpc, 0, service_id, rpc, ...)
end

function RouterMgr:call_player(service_id, player_id, rpc, ...)
    local session_id = thread_mgr:build_session_id()
    return self:forward_target(player_id, "call_player", rpc, session_id, service_id, player_id, rpc, ...)
end

function RouterMgr:send_player(service_id, player_id, rpc, ...)
    return self:forward_target(player_id, "call_player", rpc, 0, service_id, player_id, rpc, ...)
end

function RouterMgr:group_player(service_id, player_ids, rpc, ...)
    return self:forward_target(service_id + hive.id, "group_player", rpc, 0, service_id, player_ids, rpc, ...)
end

--生成针对服务的访问接口
function RouterMgr:build_service_method(service, service_id)
    local method_list = {
        ["call_%s_hash"]     = function(obj, hash_key, rpc, ...)
            return obj:call_hash(service_id, hash_key, rpc, ...)
        end,
        ["send_%s_hash"]     = function(obj, hash_key, rpc, ...)
            return obj:send_hash(service_id, hash_key, rpc, ...)
        end,
        ["call_%s_player"]   = function(obj, player_id, rpc, ...)
            return obj:call_player(service_id, player_id, rpc, ...)
        end,
        ["send_%s_player"]   = function(obj, player_id, rpc, ...)
            return obj:send_player(service_id, player_id, rpc, ...)
        end,
        ["group_%s_player"]  = function(obj, player_ids, rpc, ...)
            return obj:group_player(service_id, player_ids, rpc, ...)
        end,
        ["call_%s_random"]   = function(obj, rpc, ...)
            return obj:call_hash(service_id, mrandom(), rpc, ...)
        end,
        ["send_%s_random"]   = function(obj, rpc, ...)
            return obj:send_hash(service_id, mrandom(), rpc, ...)
        end,
        ["call_%s_master"]   = function(obj, rpc, ...)
            return obj:call_master(service_id, rpc, ...)
        end,
        ["send_%s_master"]   = function(obj, rpc, ...)
            return obj:send_master(service_id, rpc, ...)
        end,
        ["send_%s_all"]      = function(obj, rpc, ...)
            return obj:broadcast(service_id, rpc, ...)
        end,
        ["send_%s_all_self"] = function(obj, rpc, ...)
            if service_id == hive.service_id then
                event_mgr:notify_listener(rpc, ...)
            end
            return obj:broadcast(service_id, rpc, ...)
        end,
        ["collect_%s"]       = function(obj, rpc, ...)
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

--业务事件响应
-------------------------------------------------------------------------------

--服务被踢下线
function RouterMgr:rpc_service_kickout(router_id, reason)
    log_err("[RouterMgr][rpc_service_kickout] reason:{} router_id:{}", reason, id2nick(router_id))
    signal_quit()
end

--路由集群转发失败
function RouterMgr:on_forward_error(session_id, error_msg, source_id, msg_type)
    log_err("[RouterMgr][on_forward_error] session_id:{},from:{},{},msg_type:{}", session_id, id2nick(source_id), error_msg, msg_type)
    self:send_target(source_id, "reply_forward_error", session_id, error_msg, msg_type)
end

function RouterMgr:reply_forward_error(session_id, error_msg, msg_type)
    --player 消息
    if msg_type ~= 5 then
        log_err("[RouterMgr][reply_forward_error] {},{},{}", thread_mgr:get_title(session_id), error_msg, msg_type)
    end
    thread_mgr:response(session_id, false, RPC_UNREACHABLE, error_msg)
end

--心跳回复
function RouterMgr:on_heartbeat(hid, send_time, back_time)
    local netlag = hive.clock_ms - send_time
    local router = self.routers[hid]
    if router then
        router:add_netlag(netlag)
        if netlag > SECOND_MS then
            log_err("[RouterMgr][on_heartbeat] ({} <--> {}),netlag:{} ms,avg:{} ms,back_time:{}",
                    id2nick(hive.id), id2nick(hid), netlag, router:get_netlag_avg(), time_str(back_time))
        end
    end
end

hive.router_mgr = RouterMgr()

return RouterMgr
