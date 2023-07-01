--online_agent.lua
local log_info      = logger.info
local log_debug     = logger.debug
local tunpack       = table.unpack

local event_mgr     = hive.get("event_mgr")
local router_mgr    = hive.get("router_mgr")
local monitor       = hive.get("monitor")
local protobuf_mgr  = hive.get("protobuf_mgr")

local SUCCESS       = hive.enum("KernCode", "SUCCESS")
local LOGIC_FAILED  = hive.enum("KernCode", "LOGIC_FAILED")
local check_success = hive.success

local OnlineAgent   = singleton()
local prop          = property(OnlineAgent)
prop:reader("open_ids", {})
prop:reader("player_ids", {})

function OnlineAgent:__init()
    event_mgr:add_listener(self, "rpc_forward_client")
    event_mgr:add_listener(self, "rpc_forward_group_client")
    monitor:watch_service_ready(self, "online")
end

--执行远程rpc消息
function OnlineAgent:cas_dispatch_lobby(open_id, lobby_id)
    return router_mgr:call_online_hash(open_id, "rpc_cas_dispatch_lobby", open_id, lobby_id)
end

function OnlineAgent:login_dispatch_lobby(open_id)
    local ok, code = router_mgr:call_online_hash(open_id, "rpc_login_dispatch_lobby", open_id, hive.id)
    if check_success(code, ok) then
        self.open_ids[open_id] = true
    end
    return ok, code
end

function OnlineAgent:rm_dispatch_lobby(open_id)
    local ok, code = router_mgr:call_online_hash(open_id, "rpc_rm_dispatch_lobby", open_id, hive.id)
    if check_success(code, ok) then
        self.open_ids[open_id] = nil
    end
    return ok, code
end

function OnlineAgent:login_player(player_id)
    local ok, code = router_mgr:call_online_hash(player_id, "rpc_login_player", player_id, hive.id)
    if check_success(code, ok) then
        self.player_ids[player_id] = true
    end
    return ok, code
end

function OnlineAgent:logout_player(player_id)
    local ok, code = router_mgr:call_online_hash(player_id, "rpc_logout_player", player_id, hive.id)
    if check_success(code, ok) then
        self.player_ids[player_id] = nil
    end
    return ok, code
end

function OnlineAgent:query_openid(open_id)
    return router_mgr:call_online_hash(open_id, "rpc_query_openid", open_id)
end

function OnlineAgent:query_player(player_id)
    return router_mgr:call_online_hash(player_id, "rpc_query_player", player_id)
end

--有序
function OnlineAgent:call_lobby(player_id, rpc, ...)
    return router_mgr:call_online_hash(player_id, "rpc_call_lobby", player_id, rpc, ...)
end

function OnlineAgent:send_lobby(player_id, rpc, ...)
    return router_mgr:send_online_hash(player_id, "rpc_send_lobby", player_id, rpc, ...)
end

function OnlineAgent:call_client(player_id, cmd_id, msg)
    msg = self:encode_msg(player_id, cmd_id, msg)
    return router_mgr:call_online_hash(player_id, "rpc_call_client", player_id, cmd_id, msg)
end

function OnlineAgent:send_client(player_id, cmd_id, msg)
    msg = self:encode_msg(player_id, cmd_id, msg)
    return router_mgr:send_online_hash(player_id, "rpc_send_client", player_id, cmd_id, msg)
end

function OnlineAgent:send_group_client(players, cmd_id, msg)
    msg = self:encode_msg(0, cmd_id, msg)
    if players and #players < 5 then
        --人少直接1v1转发
        for _, player_id in pairs(players) do
            router_mgr:send_online_hash(player_id, "rpc_send_client", player_id, cmd_id, msg)
        end
    else
        router_mgr:send_lobby_all_self("rpc_forward_group_client", players, cmd_id, msg)
    end
end

function OnlineAgent:send_lobby_client(lobby_id, player_id, cmd_id, msg)
    msg = self:encode_msg(player_id, cmd_id, msg)
    router_mgr:send_target(lobby_id, "rpc_forward_client", player_id, cmd_id, msg)
end

function OnlineAgent:encode_msg(player_id, cmd_id, msg)
    log_debug("[S2C] player_id:%s,cmd_id:%s,cmd:%s,msg:%s", player_id, cmd_id, protobuf_mgr:msg_name(cmd_id), msg)
    return protobuf_mgr:encode(cmd_id, msg)
end

--rpc处理
------------------------------------------------------------------
--透传给client的消息
--需由player_mgr实现on_forward_client，给client发消息
function OnlineAgent:rpc_forward_client(player_id, cmd_id, msg)
    local ok, res = tunpack(event_mgr:notify_listener("on_forward_client", player_id, cmd_id, msg))
    return ok and SUCCESS or LOGIC_FAILED, res
end

function OnlineAgent:rpc_forward_group_client(player_ids, cmd_id, msg)
    local ok, res = tunpack(event_mgr:notify_listener("on_forward_group_client", player_ids, cmd_id, msg))
    return ok and SUCCESS or LOGIC_FAILED, res
end

-- Online服务已经ready
function OnlineAgent:on_service_ready(id, service_name)
    log_info("[OnlineAgent][on_service_ready]->service_name:%s", service.id2nick(id))
    self:on_rebuild_online()
end

-- online数据恢复
function OnlineAgent:on_rebuild_online()
    for open_id, _ in pairs(self.open_ids) do
        router_mgr:send_online_hash(open_id, "rpc_login_dispatch_lobby", open_id, hive.id)
    end
    for player_id, _ in pairs(self.player_ids) do
        router_mgr:send_online_hash(player_id, "rpc_login_player", player_id, hive.id)
    end
end

hive.online_agent = OnlineAgent()

return OnlineAgent
