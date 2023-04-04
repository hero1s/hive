--router_server.lua
local log_err      = logger.err
local log_info     = logger.info
local log_debug    = logger.debug
local sidhash      = service.hash
local tinsert      = table.insert

local FlagMask     = enum("FlagMask")
local KernCode     = enum("KernCode")
local RpcServer    = import("network/rpc_server.lua")

local socket_mgr   = hive.get("socket_mgr")
local thread_mgr   = hive.get("thread_mgr")
local event_mgr    = hive.get("event_mgr")

local RouterServer = singleton()
local prop         = property(RouterServer)
prop:accessor("rpc_server", nil)
function RouterServer:__init()
    self:setup()
    event_mgr:add_listener(self, "rpc_sync_router_info")
end

function RouterServer:setup()
    local port      = environ.number("HIVE_ROUTER_PORT", 9001)
    --启动server
    self.rpc_server = RpcServer(self, "0.0.0.0", port, true)
    service.make_node(self.rpc_server:get_port())
    socket_mgr.set_router_id(hive.id)
end

--其他服务器节点关闭
function RouterServer:on_client_error(client, client_token, err)
    local master_id = socket_mgr.map_token(client.id, 0)
    self:update_router_node_info(hive.id, client.id, 0)
    log_info("[RouterServer][on_client_error] %s lost: %s,master:%s", client.name, err, master_id)
end

--accept事件
function RouterServer:on_client_accept(client)
    log_info("[RouterServer][on_client_accept] new connection, token=%s", client.token)
    client.on_forward_error     = function(session_id, error_msg)
        thread_mgr:fork(function()
            log_err("[RouterServer][on_client_accept] on_forward_error:%s, session_id=%s,%s", error_msg, session_id, client.name)
            client.call(session_id, FlagMask.RES, hive.id, "on_forward_error", false, KernCode.RPC_UNREACHABLE, error_msg)
        end)
    end
    client.on_forward_broadcast = function(session_id, broadcast_num)
        thread_mgr:fork(function()
            client.call(session_id, FlagMask.RES, hive.id, "on_forward_broadcast", true, KernCode.SUCCESS, broadcast_num)
        end)
    end
end

--todo 后续优化同步机制 toney
function RouterServer:update_router_node_info(router_id, target_id, status)
    socket_mgr.map_router_node(router_id, target_id, status)
    local nodes = {}
    if status == 0 then
        tinsert(nodes, router_id)
    else
        for _, client in self.rpc_server:iterator() do
            tinsert(nodes, client.id)
        end
    end
    for _, client in self.rpc_server:iterator() do
        if client.service_name == "router" then
            self.rpc_server:send(client, "rpc_sync_router_info", router_id, nodes, status)
        end
    end
end

--rpc事件处理
------------------------------------------------------------------
function RouterServer:rpc_sync_router_info(router_id, target_ids, status)
    log_debug("[RouterServer][rpc_sync_router_info] router_id:%s,target_ids:%s,status:%s", router_id, target_ids, status)
    if #target_ids > 1 then
        socket_mgr.map_router_node(router_id, 0, 0)
    end
    for _, id in pairs(target_ids) do
        socket_mgr.map_router_node(router_id, id, status)
    end
end

-- 会话信息
function RouterServer:on_client_register(client, node_info)
    log_debug("[RouterServer][on_client_register] %s", node_info)
    local service_hash = sidhash(client.service_id)
    --固定hash自动设置为最大index服务[约定固定hash服务的index为连续的1-n,且运行过程中不能扩容]
    local hash_value   = service_hash > 0 and client.index or 0
    local master_id    = socket_mgr.map_token(client.id, client.token, hash_value)
    self:update_router_node_info(hive.id, client.id, 1)
    log_info("[RouterServer][service_register] service: %s,hash:%s,master:%s", client.name, service_hash, master_id)
end

-- 心跳
function RouterServer:on_client_beat(client, is_ready)


end

hive.router_server = RouterServer()

return RouterServer
