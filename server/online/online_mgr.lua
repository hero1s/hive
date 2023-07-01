--online_mgr.lua

--本模块维护了所有在线玩家的索引,即: player_id --> lobbysvr-id
--当然,不在线的玩家查询结果就是nil:)
--这里维护的在线状态仅供一般性消息中转用,登录状态判定以数据库中记录为准
local pairs            = pairs
local tunpack          = table.unpack
local tpack            = table.pack
local tremove          = table.remove
local log_info         = logger.info
local log_warn         = logger.warn
local log_err          = logger.err
local KernCode         = enum("KernCode")
local SUCCESS          = KernCode.SUCCESS
local FAILED           = KernCode.FAILED
local id2nick          = service.id2nick
local event_mgr        = hive.get("event_mgr")
local router_mgr       = hive.get("router_mgr")
local monitor          = hive.get("monitor")
local update_mgr       = hive.get("update_mgr")
local due_time <const> = 3600

local OnlineMgr        = singleton()
local prop             = property(OnlineMgr)
prop:reader("sync_status", true)
function OnlineMgr:__init()
    self.lobbys        = {}     --在线玩家
    self.lobby_players = {}     --lobby玩家索引
    self.oid2lobby     = {}     --玩家 open_id 到 lobby分布 map<oid, lobby>

    --初始化，注册事件
    event_mgr:add_listener(self, "rpc_cas_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_login_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_rm_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_login_player")
    event_mgr:add_listener(self, "rpc_logout_player")
    event_mgr:add_listener(self, "rpc_query_openid")
    event_mgr:add_listener(self, "rpc_query_player")
    event_mgr:add_listener(self, "rpc_sync_openid_info")
    event_mgr:add_listener(self, "rpc_sync_player_info")
    event_mgr:add_listener(self, "rpc_call_client")
    event_mgr:add_listener(self, "rpc_call_lobby")
    event_mgr:add_listener(self, "rpc_send_client")
    event_mgr:add_listener(self, "rpc_send_lobby")

    monitor:watch_service_close(self, "lobby")

    update_mgr:attach_minute(self)
end

function OnlineMgr:on_minute()
    local cur_time = hive.now
    for k, v in pairs(self.oid2lobby) do
        if not v.login_time and cur_time > v.dtime then
            self.oid2lobby[k] = nil
            log_warn("[OnlineMgr][on_minute] remove due open_id:%s", k)
        end
    end
end

--rpc协议处理
------------------------------------------------------------------------------
--lobby失活时,所有indexsvr清除对应的索引数据
function OnlineMgr:on_service_close(id, service_name)
    if service_name == "lobby" then
        local lobby_data = self.lobby_players[id]
        for player_id in pairs(lobby_data or {}) do
            self.lobbys[player_id] = nil
        end
        self.lobby_players[id] = {}
        -- 清理lobby分配信息 存在bug,需要处理 toney
        for oid, lobby in pairs(self.oid2lobby) do
            if lobby.lobby_id == id then
                self.oid2lobby[oid] = nil
            end
        end
    end
end

--角色分配lobby
--类cas操作，如果lobby_id一致或者为nill返回lobby_id，否则返回indexsvr上的原值
function OnlineMgr:rpc_cas_dispatch_lobby(open_id, lobby_id)
    local lid = self:find_lobby_dispatch(open_id)
    if not lid then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, dtime = hive.now + due_time }
        lid                     = lobby_id
    end
    log_info("[OnlineMgr][rpc_cas_dispatch_lobby] open_id:%s,%s-->%s", open_id, id2nick(lobby_id), id2nick(lid))
    return SUCCESS, lid
end

-- 分配的lobby登录成功
function OnlineMgr:rpc_login_dispatch_lobby(open_id, lobby_id)
    local lobby = self.oid2lobby[open_id]
    if not lobby then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, login_time = hive.now }
        self:sync_openid_info(open_id, lobby_id, true)
        log_info("[OnlineMgr][rpc_login_dispatch_lobby] open_id:%s,%s", open_id, id2nick(lobby_id))
        return SUCCESS
    end
    if lobby.lobby_id ~= lobby_id then
        log_err("[OnlineMgr][rpc_login_dispatch_lobby] the lobby is error:%s,%s--%s", open_id, id2nick(lobby_id), lobby)
        return FAILED
    end
    lobby.login_time = hive.now
    log_info("[OnlineMgr][rpc_login_dispatch_lobby] open_id:%s,%s", open_id, id2nick(lobby_id))
    self:sync_openid_info(open_id, lobby_id, true)
    return SUCCESS
end

-- 移除lobby分配
function OnlineMgr:rpc_rm_dispatch_lobby(open_id, lobby_id)
    local lobby = self.oid2lobby[open_id]
    if not lobby or lobby.lobby_id ~= lobby_id then
        log_err("[OnlineMgr][rpc_rm_dispatch_lobby] the lobby is error:%s,%s--%s", open_id, lobby_id, lobby)
        return SUCCESS
    end
    self.oid2lobby[open_id] = nil
    self:sync_openid_info(open_id, lobby_id, false)
    log_info("[OnlineMgr][rpc_rm_dispatch_lobby] open_id:%s,%s", open_id, id2nick(lobby_id))
    return SUCCESS
end

-- 获取玩家当前的小区分配信息
function OnlineMgr:find_lobby_dispatch(open_id)
    local lobby = self.oid2lobby[open_id]
    if not lobby then
        return nil
    end
    return lobby.lobby_id
end

--角色登陆
function OnlineMgr:rpc_login_player(player_id, lobby_id)
    log_info("[OnlineMgr][rpc_login_player]: %s, %s", player_id, id2nick(lobby_id))
    self.lobbys[player_id] = lobby_id
    if not self.lobby_players[lobby_id] then
        self.lobby_players[lobby_id] = {}
    end
    self.lobby_players[lobby_id][player_id] = true
    self:sync_player_info(player_id, lobby_id, true)
    return SUCCESS
end

--角色登出
function OnlineMgr:rpc_logout_player(player_id, lobby_id)
    log_info("[OnlineMgr][rpc_logout_player]: %s,%s", player_id, id2nick(lobby_id))
    local lid = self.lobbys[player_id]
    if lid == lobby_id then
        self.lobbys[player_id]                  = nil
        self.lobby_players[lobby_id][player_id] = nil
    else
        log_err("[OnlineMgr][rpc_logout_player] the lobb_id is error:%s,%s--%s", player_id, lobby_id, lid)
    end
    self:sync_player_info(player_id, lobby_id, false)
    return SUCCESS
end

--获取玩家所在的lobby
function OnlineMgr:rpc_query_openid(open_id)
    local lobby = self.oid2lobby[open_id]
    if lobby then
        return SUCCESS, lobby.lobby_id
    end
    return SUCCESS, 0
end

--获取玩家所在的lobby
function OnlineMgr:rpc_query_player(player_id)
    return SUCCESS, self.lobbys[player_id] or 0
end

--同步open_id数据到其它online
function OnlineMgr:sync_openid_info(open_id, lobby_id, online)
    if self.sync_status then
        router_mgr:send_online_all("rpc_sync_openid_info", open_id, lobby_id, online)
    end
end

function OnlineMgr:rpc_sync_openid_info(open_id, lobby_id, online)
    log_info("[OnlineMgr][rpc_sync_openid_info] open_id:%s,lobby:%s,%s", open_id, id2nick(lobby_id), online)
    if online then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, login_time = hive.now }
    else
        self.oid2lobby[open_id] = nil
    end
end

--同步player_id数据到其它online
function OnlineMgr:sync_player_info(player_id, lobby_id, online)
    if self.sync_status then
        router_mgr:send_online_all("rpc_sync_player_info", player_id, lobby_id, online)
    end
end

function OnlineMgr:rpc_sync_player_info(player_id, lobby_id, online)
    log_info("[OnlineMgr][rpc_sync_player_info] player_id:%s,lobby:%s,%s", player_id, id2nick(lobby_id), online)
    if online then
        self.lobbys[player_id] = lobby_id
        if not self.lobby_players[lobby_id] then
            self.lobby_players[lobby_id] = {}
        end
        self.lobby_players[lobby_id][player_id] = true
    else
        self.lobbys[player_id]                  = nil
        self.lobby_players[lobby_id][player_id] = nil
    end
end

-------------------------------------------------------------------
--根据玩家所在的lobby转发消息
function OnlineMgr:rpc_call_lobby(player_id, rpc, ...)
    local lobby = self.lobbys[player_id]
    if not lobby then
        return KernCode.PLAYER_NOT_EXIST, "player not online!"
    end
    local res = tpack(router_mgr:call_target(lobby, rpc, ...))
    local ok  = tremove(res, 1)
    if not ok then
        local code = #res > 0 and res[1] or nil
        return KernCode.RPC_FAILED, code
    end
    return tunpack(res)
end

--根据玩家所在的lobby转发消息
function OnlineMgr:rpc_send_lobby(player_id, rpc, ...)
    local lobby = self.lobbys[player_id]
    if lobby then
        router_mgr:send_target(lobby, rpc, ...)
    end
end

--根据玩家所在的lobby转发消息，然后转发给客户端
function OnlineMgr:rpc_call_client(player_id, cmd_id, msg)
    local lobby = self.lobbys[player_id]
    if not lobby then
        return KernCode.PLAYER_NOT_EXIST, "player not online!"
    end
    local ok, codeoe, res = router_mgr:call_target(lobby, "rpc_forward_client", player_id, cmd_id, msg)
    if not ok then
        return KernCode.RPC_FAILED, codeoe
    end
    return codeoe, res
end

function OnlineMgr:rpc_send_client(player_id, cmd_id, msg)
    local lobby = self.lobbys[player_id]
    if lobby then
        router_mgr:send_target(lobby, "rpc_forward_client", player_id, cmd_id, msg)
    end
end

-- export
hive.online_mgr = OnlineMgr()

return OnlineMgr
