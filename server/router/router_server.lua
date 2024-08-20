--router_server.lua
local luabus        = luabus
local log_info      = logger.info
local log_debug     = logger.debug
local sidhash       = service.hash
local id2nick       = service.id2nick
local sname2sid     = service.name2sid

local FlagMask      = enum("FlagMask")
local PeriodTime    = enum("PeriodTime")
local ServiceStatus = enum("ServiceStatus")
local RpcServer     = import("network/rpc_server.lua")

local SUCCESS       = hive.enum("KernCode", "SUCCESS")

local thread_mgr    = hive.get("thread_mgr")
local event_mgr     = hive.get("event_mgr")
local timer_mgr     = hive.get("timer_mgr")

local RouterServer  = singleton()
local prop          = property(RouterServer)
prop:accessor("rpc_server", nil)
prop:accessor("change", false)
function RouterServer:__init()
    self:setup()
    event_mgr:add_listener(self, "rpc_sync_router_info")
    event_mgr:add_listener(self, "rpc_sync_player_service")
    event_mgr:add_listener(self, "rpc_set_player_service")
    event_mgr:add_listener(self, "rpc_query_player_service")

    timer_mgr:loop(PeriodTime.MINUTE_MS, function()
        self:sync_all_node_info()
    end)
end

function RouterServer:setup()
    local port      = environ.number("HIVE_ROUTER_PORT", 9001)
    --启动server
    self.rpc_server = RpcServer(self, "0.0.0.0", port, environ.status("HIVE_ADDR_INDUCE"))
    self.router_sid = sname2sid("router")
    service.make_node(self.rpc_server:get_port())
    luabus.set_router_id(hive.id)
    --设置服务表
    local services = service.services()
    for service, service_id in pairs(services) do
        luabus.set_service_name(service_id, service)
    end
end

--其他服务器节点关闭
function RouterServer:on_client_error(client, client_token, err)
    local master_id = luabus.map_token(client.id, 0)
    self:update_router_node_info(client, 0)
    log_info("[RouterServer][on_client_error] {} lost: {},master:{}", client.name, err, id2nick(master_id))
    luabus.clean_player_sid(client.id)
end

--accept事件
function RouterServer:on_client_accept(client)
    client.on_forward_error     = function(session_id, error_msg, source_id, msg_type)
        thread_mgr:fork(function()
            client.call(session_id, FlagMask.RES, hive.id, "reply_forward_error", error_msg, msg_type)
            --为了方便错误日志暂时先留着 toney
            --self.rpc_server:callback(client, session_id, false, UNREACHABLE, error_msg, msg_type)
        end)
    end
    client.on_forward_broadcast = function(session_id, broadcast_num)
        thread_mgr:fork(function()
            self.rpc_server:callback(client, session_id, true, SUCCESS, broadcast_num)
        end)
    end
end

function RouterServer:update_router_node_info(client, status)
    local router_id = hive.id
    local target_id = client.id
    luabus.map_router_node(router_id, target_id, status)
    if status == 0 then
        self:broadcast_router("rpc_sync_router_info", router_id, { target_id }, status)
    end
    self.change = true
end

function RouterServer:sync_all_node_info(force)
    if self.change or force then
        local nodes = self.rpc_server:service_nodes(0)
        self:broadcast_router("rpc_sync_router_info", hive.id, nodes, 1)
        log_info("[RouterServer][sync_all_node_info] router:{},service:{}", self.rpc_server:service_count(hive.service_id), self.rpc_server:service_count(0))
        self.change = false
    end
end

function RouterServer:broadcast_router(rpc, ...)
    self.rpc_server:servicecast(self.router_sid, rpc, ...)
end

--rpc事件处理
------------------------------------------------------------------
function RouterServer:rpc_sync_router_info(router_id, target_ids, status)
    log_debug("[RouterServer][rpc_sync_router_info] router_id:{},target_ids:{},status:{}", id2nick(router_id), #target_ids, status)
    if #target_ids > 1 then
        luabus.map_router_node(router_id, 0, 0)
    end
    for _, id in pairs(target_ids) do
        luabus.map_router_node(router_id, id, status)
    end
end

function RouterServer:rpc_sync_player_service(player_id, sid, login)
    log_info("[RpcServer][rpc_sync_player_service] player_id:{},sid:{},login:{}", player_id, sid, login)
    luabus.set_player_service(player_id, sid, login)
end

function RouterServer:rpc_set_player_service(client, player_id, sid, login)
    log_info("[RpcServer][rpc_set_player_service] player_id:{},sid:{},login:{}", player_id, sid, login)
    luabus.set_player_service(player_id, sid, login)
    self:broadcast_router("rpc_sync_player_service", player_id, sid, login)
end

function RouterServer:rpc_query_player_service(client, player_id, service_id)
    return luabus.find_player_sid(player_id, service_id)
end

-- 会话信息
function RouterServer:on_client_register(client, node_info)
    log_debug("[RouterServer][on_client_register] {}", node_info)
    local service_hash = sidhash(client.service_id)
    --固定hash自动设置为最大index服务[约定固定hash服务的index为连续的1-n,且运行过程中不能扩容]
    local hash_value   = service_hash > 0 and client.index or 0
    local master_id    = luabus.map_token(client.id, client.token, hash_value)
    self:update_router_node_info(client, 1)
    log_info("[RouterServer][service_register] service: {},hash:{},master:{}", client.name, service_hash, master_id)
end

-- 心跳
function RouterServer:on_client_beat(client, status_info)
    local status = status_info.status
    --设置hash限流,挂起状态不再分配hash消息派发
    if status < ServiceStatus.RUN or status == ServiceStatus.HALT then
        if not client.ban_hash then
            log_info("[RouterServer][on_client_beat] add ban hash server {}", client.name)
            luabus.set_node_status(client.id, 1)
            client.ban_hash = true
        end
    else
        if client.ban_hash then
            luabus.set_node_status(client.id, 0)
            client.ban_hash = false
            log_info("[RouterServer][on_client_beat] remove ban hash server {}", client.name)
        end
    end
end

hive.router_server = RouterServer()

return RouterServer
