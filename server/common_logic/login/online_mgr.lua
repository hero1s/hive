--online_mgr.lua

--本模块维护了所有在线玩家的索引,即: open_id --> lobbysvr-id
--当然,不在线的玩家查询结果就是nil:)
local pairs            = pairs
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
local gm_agent         = hive.get("gm_agent")

local GMType           = enum("GMType")
local due_time <const> = 3600

local OnlineMgr        = singleton()
local prop             = property(OnlineMgr)
prop:reader("oid2lobby", {})     --玩家 open_id 到 lobby分布 map<oid, lobby>
prop:reader("rebuilds", {})      --重建
function OnlineMgr:__init()
    --初始化，注册事件
    event_mgr:add_listener(self, "rpc_cas_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_login_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_rm_dispatch_lobby")
    event_mgr:add_listener(self, "rpc_query_openid")
    event_mgr:add_listener(self, "rpc_sync_openid_info")
    event_mgr:add_listener(self, "rpc_rebuild_login_lobby")

    event_mgr:add_vote(self, "vote_ready_service")
    monitor:watch_service_close(self, "lobby")

    update_mgr:attach_minute(self)
    self:register_gm()
end

function OnlineMgr:register_gm()
    local cmd_list = {
        { group = "运维", gm_type = GMType.SYSTEM, name = "gm_clear_login_lobby", desc = "清空lobby登录信息", args = "index|integer" },
    }
    gm_agent:insert_command(cmd_list, self)
end

function OnlineMgr:gm_clear_login_lobby(index)
    self:clear_lobby_openid(service.make_id("lobby", index))
    return { code = 0 }
end

function OnlineMgr:on_minute()
    local cur_time = hive.now
    for k, v in pairs(self.oid2lobby) do
        if not v.login_time and cur_time > v.dtime then
            self.oid2lobby[k] = nil
            log_warn("[OnlineMgr][on_minute] remove due open_id:{}", k)
        end
    end
end

--rpc协议处理
------------------------------------------------------------------------------
function OnlineMgr:vote_ready_service()
    local info = monitor:query_services("lobby")
    if not info then
        return false
    end
    log_info("[OnlineMgr][vote_ready_service] {},count:{}", info.sids, info.count)
    --{ sids = sids, count = count }
    for _, index in pairs(info.sids) do
        local id = service.make_id("lobby", index)
        if not self.rebuilds[id] then
            log_warn("[OnlineMgr][vote_ready_service] not rebuild lobby:{}", id2nick(index))
            return false
        end
    end
    return true
end

function OnlineMgr:clear_lobby_openid(lobby_id)
    log_info("[OnlineMgr][clear_lobby_openid] lobby:{}", id2nick(lobby_id))
    for oid, lobby in pairs(self.oid2lobby) do
        if lobby.lobby_id == lobby_id then
            self.oid2lobby[oid] = nil
        end
    end
end

--lobby失活时,为保证数据一致性,如果lobby不再拉起,需手动清理
function OnlineMgr:on_service_close(id, service_name)
    if service_name == "lobby" then
        self.rebuilds[id] = nil
    end
end

function OnlineMgr:rpc_rebuild_login_lobby(open_ids, lobby_id)
    log_info("[OnlineMgr][rpc_rebuild_login_lobby] open_ids:{},lobby:{}", #open_ids, id2nick(lobby_id))
    self:clear_lobby_openid(lobby_id)
    for _, open_id in pairs(open_ids) do
        self:rpc_login_dispatch_lobby(open_id, lobby_id)
    end
    self.rebuilds[lobby_id] = true
    return SUCCESS
end

--角色分配lobby
--类cas操作，如果lobby_id一致或者为nill返回lobby_id，否则返回indexsvr上的原值
function OnlineMgr:rpc_cas_dispatch_lobby(open_id, lobby_id)
    local lid = self:find_lobby_dispatch(open_id)
    if not lid then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, dtime = hive.now + due_time }
        lid                     = lobby_id
    end
    log_info("[OnlineMgr][rpc_cas_dispatch_lobby] open_id:{},{}-->{}", open_id, id2nick(lobby_id), id2nick(lid))
    return SUCCESS, lid
end

-- 分配的lobby登录成功
function OnlineMgr:rpc_login_dispatch_lobby(open_id, lobby_id)
    local lobby = self.oid2lobby[open_id]
    if not lobby then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, login_time = hive.now }
        self:sync_openid_info(open_id, lobby_id, true)
        log_info("[OnlineMgr][rpc_login_dispatch_lobby] open_id:{},{}", open_id, id2nick(lobby_id))
        return SUCCESS
    end
    if lobby.lobby_id ~= lobby_id then
        log_err("[OnlineMgr][rpc_login_dispatch_lobby] the lobby is error:{},{}--{}", open_id, id2nick(lobby_id), lobby)
        return FAILED
    end
    lobby.login_time = hive.now
    log_info("[OnlineMgr][rpc_login_dispatch_lobby] open_id:{},{}", open_id, id2nick(lobby_id))
    self:sync_openid_info(open_id, lobby_id, true)
    return SUCCESS
end

-- 移除lobby分配
function OnlineMgr:rpc_rm_dispatch_lobby(open_id, lobby_id)
    local lobby = self.oid2lobby[open_id]
    if not lobby or lobby.lobby_id ~= lobby_id then
        log_warn("[OnlineMgr][rpc_rm_dispatch_lobby] the lobby is error:{},{}--{}", open_id, lobby_id, lobby)
        return SUCCESS
    end
    self.oid2lobby[open_id] = nil
    self:sync_openid_info(open_id, lobby_id, false)
    log_info("[OnlineMgr][rpc_rm_dispatch_lobby] open_id:{},{}", open_id, id2nick(lobby_id))
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

--获取玩家所在的lobby
function OnlineMgr:rpc_query_openid(open_id)
    local lobby = self.oid2lobby[open_id]
    if lobby then
        return SUCCESS, lobby.lobby_id
    end
    return SUCCESS, 0
end

--同步open_id数据到其它online
function OnlineMgr:sync_openid_info(open_id, lobby_id, online)
    router_mgr:send_login_all("rpc_sync_openid_info", open_id, lobby_id, online)
end

function OnlineMgr:rpc_sync_openid_info(open_id, lobby_id, online)
    log_info("[OnlineMgr][rpc_sync_openid_info] open_id:{},lobby:{},{}", open_id, id2nick(lobby_id), online)
    if online then
        self.oid2lobby[open_id] = { lobby_id = lobby_id, login_time = hive.now }
    else
        self.oid2lobby[open_id] = nil
    end
end

-------------------------------------------------------------------

-- export
hive.online_mgr = OnlineMgr()

return OnlineMgr
