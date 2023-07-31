--router_server.lua
local lbus          = require("luabus")
local log_info      = logger.info
local log_debug     = logger.debug
local sidhash       = service.hash
local id2nick       = service.id2nick
local tinsert       = table.insert

local FlagMask      = enum("FlagMask")
local KernCode      = enum("KernCode")
local ServiceStatus = enum("ServiceStatus")
local RpcServer     = import("network/rpc_server.lua")

local thread_mgr    = hive.get("thread_mgr")
local event_mgr     = hive.get("event_mgr")
local update_mgr    = hive.get("update_mgr")

local RouterServer  = singleton()
local prop          = property(RouterServer)
prop:accessor("rpc_server", nil)
prop:accessor("change", false)
function RouterServer:__init()
    self:setup()
    event_mgr:add_listener(self, "rpc_sync_router_info")

    update_mgr:attach_minute(self)
end

function RouterServer:setup()
    local port      = environ.number("HIVE_ROUTER_PORT", 9001)
    --启动server
    self.rpc_server = RpcServer(self, "0.0.0.0", port, environ.status("HIVE_ADDR_INDUCE"))
    service.make_node(self.rpc_server:get_port())
    lbus.set_router_id(hive.id)
end

function RouterServer:on_minute()
    if self.change then
        self:sync_all_node_info()
        self.change = false
    end
    log_info("[RouterServer][on_minute] router:%s,service:%s", self.rpc_server:service_count(hive.service_id), self.rpc_server:service_count(0))
end

--其他服务器节点关闭
function RouterServer:on_client_error(client, client_token, err)
    local master_id = lbus.map_token(client.id, 0)
    self:update_router_node_info(client, 0)
    log_info("[RouterServer][on_client_error] %s lost: %s,master:%s", client.name, err, id2nick(master_id))
end

--accept事件
function RouterServer:on_client_accept(client)
    log_info("[RouterServer][on_client_accept] new connection, token=%s,ip:%s", client.token, client.ip)
    client.on_forward_error     = function(session_id, error_msg)
        thread_mgr:fork(function()
            client.call(session_id, FlagMask.RES, hive.id, "on_forward_error", false, KernCode.RPC_UNREACHABLE, error_msg)
        end)
    end
    client.on_forward_broadcast = function(session_id, broadcast_num)
        thread_mgr:fork(function()
            client.call(session_id, FlagMask.RES, hive.id, "on_forward_broadcast", true, KernCode.SUCCESS, broadcast_num)
        end)
    end
end

function RouterServer:update_router_node_info(client, status)
    local router_id = hive.id
    local target_id = client.id
    lbus.map_router_node(router_id, target_id, status)
    if status == 0 then
        self:broadcast_router("rpc_sync_router_info", router_id, { target_id }, status)
    end
    self.change = true
end

function RouterServer:sync_all_node_info()
    local nodes = {}
    for _, client in self.rpc_server:iterator() do
        if client.id then
            tinsert(nodes, client.id)
        end
    end
    self:broadcast_router("rpc_sync_router_info", hive.id, nodes, 1)
end

function RouterServer:broadcast_router(rpc, ...)
    for _, client in self.rpc_server:iterator() do
        if client.service_name == "router" then
            self.rpc_server:send(client, rpc, ...)
        end
    end
end

--rpc事件处理
------------------------------------------------------------------
function RouterServer:rpc_sync_router_info(router_id, target_ids, status)
    log_debug("[RouterServer][rpc_sync_router_info] router_id:%s,target_ids:%s,status:%s", id2nick(router_id), #target_ids, status)
    if #target_ids > 1 then
        lbus.map_router_node(router_id, 0, 0)
    end
    for _, id in pairs(target_ids) do
        lbus.map_router_node(router_id, id, status)
    end
end

-- 会话信息
function RouterServer:on_client_register(client, node_info)
    log_debug("[RouterServer][on_client_register] %s", node_info)
    local service_hash = sidhash(client.service_id)
    --固定hash自动设置为最大index服务[约定固定hash服务的index为连续的1-n,且运行过程中不能扩容]
    local hash_value   = service_hash > 0 and client.index or 0
    local master_id    = lbus.map_token(client.id, client.token, hash_value)
    self:update_router_node_info(client, 1)
    log_info("[RouterServer][service_register] service: %s,hash:%s,master:%s", client.name, service_hash, master_id)
end

-- 心跳
function RouterServer:on_client_beat(client, status_info)
    local status = status_info.status
    --设置hash限流,挂起状态不再分配hash消息派发
    if status == ServiceStatus.HALT and hive.is_runing() then
        log_info("[RouterServer][on_client_beat] add ban hash server %s", client.name)
        lbus.set_node_status(client.id, 1)
        client.ban_hash = true
    elseif client.ban_hash then
        lbus.set_node_status(client.id, 0)
        client.ban_hash = false
        log_info("[RouterServer][on_client_beat] remove ban hash server %s", client.name)
    end
end

hive.router_server = RouterServer()

return RouterServer
