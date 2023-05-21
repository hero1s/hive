local log_warn  = logger.warn
local log_debug = logger.debug

local event_mgr = hive.get("event_mgr")

local CSCmdID   = ncmd_cs.NCmdId

local Gateway   = singleton()
local prop      = property(Gateway)
prop:reader("client_mgr", nil)          --会话管理器

function Gateway:__init()
    -- 网络事件监听
    event_mgr:add_listener(self, "on_session_cmd")
    event_mgr:add_listener(self, "on_session_error")
    event_mgr:add_listener(self, "on_socket_accept")
    -- rpc消息监听
    event_mgr:add_listener(self, "rpc_close_session")
    event_mgr:add_listener(self, "rpc_forward_client")
    event_mgr:add_listener(self, "rpc_groupcast_client")
    event_mgr:add_listener(self, "rpc_broadcast_client")
    -- cs协议监听

end

local dx_cmd_route_table = {
    [CSCmdID.NID_HEARTBEAT_REQ] = "on_heartbeat_req"
}

function Gateway:rpc_close_session(token)
    self.client_mgr:close_session_by_token(token)
end

--转发给客户端
function Gateway:rpc_forward_client(token, cmd_id, data, session_id)
    local session = self.client_mgr:get_session_by_token(token)
    if session then
        if session_id and session_id > 0 then
            self.client_mgr:callback_pack(session, cmd_id, data, session_id)
        else
            self.client_mgr:send_pack(session, cmd_id, data, session_id)
        end
        return true
    end
    return false
end

--组发消息
function Gateway:rpc_groupcast_client(tokens, cmd_id, data)
    for _, token in pairs(tokens) do
        self:rpc_forward_client(token, cmd_id, data)
    end
end

--广播给客户端
function Gateway:rpc_broadcast_client(cmd_id, data)
    self.client_mgr:broadcast(cmd_id, data)
end

--心跳协议
function Gateway:on_heartbeat_req(session, body, session_id)
    local sserial  = body.serial
    local data_res = { serial = sserial, time = hive.now }
    self.client_mgr:callback_pack(session, CSCmdID.NID_HEARTBEAT_RES, data_res, session_id)
end

--连接信息
----------------------------------------------------------------------
--客户端连上
function Gateway:on_socket_accept(session)
    log_debug("[Gateway][on_socket_accept] %s connected!", session.token)
end

--客户端连接断开
function Gateway:on_session_error(session, token, err)
    log_warn("[Gateway][on_session_error] session(%s) lost, because: %s!", token, err)
    hive.send_master("on_session_error", token, err)
end

--客户端消息分发
function Gateway:on_session_cmd(session, cmd_id, body, session_id)
    --转发消息
    local func_name = dx_cmd_route_table[cmd_id]
    if func_name then
        self[func_name](self, session, body, session_id)
    else
        hive.send_master("on_session_cmd", session.token, cmd_id, body, session_id)
    end
end

hive.gateway = Gateway()

return Gateway
