--gm_mgr.lua
import("basic/cmdline.lua")
import("agent/online_agent.lua")

local lguid       = require("lguid")
local gm_page      = nil
local HttpServer   = import("network/http_server.lua")

local json_decode  = hive.json_decode
local guid_index   = lguid.guid_index
local tunpack      = table.unpack
local env_get      = environ.get
local smake_id     = service.make_id
local log_err      = logger.err
local log_debug    = logger.debug
local readfile     = io_ext.readfile
local strim        = string_ext.trim

local GMType       = enum("GMType")
local KernCode     = enum("KernCode")
local SUCCESS      = KernCode.SUCCESS

local cmdline      = hive.get("cmdline")
local event_mgr    = hive.get("event_mgr")
local router_mgr   = hive.get("router_mgr")
local online_agent = hive.get("online")

local AdminMgr     = singleton()
local prop         = property(AdminMgr)
prop:reader("http_server", nil)
prop:reader("deploy", "local")
prop:reader("services", {})
prop:reader("monitors", {})

function AdminMgr:__init()
    gm_page = readfile("../hive/server/admin/gm_page.html")

    --监听事件
    event_mgr:add_listener(self, "rpc_register_command")
    event_mgr:add_listener(self, "rpc_execute_command")
    event_mgr:add_listener(self, "rpc_execute_message")

    --创建HTTP服务器
    local server = HttpServer(env_get("HIVE_ADMIN_HTTP"))
    server:register_get("/", "on_gm_page", self)
    server:register_get("/gmlist", "on_gmlist", self)
    server:register_get("/monitors", "on_monitors", self)
    server:register_post("/command", "on_command", self)
    server:register_post("/monitor", "on_monitor", self)
    server:register_post("/message", "on_message", self)
    self.http_server = server
end

--rpc请求
---------------------------------------------------------------------
--注册GM
function AdminMgr:rpc_register_command(command_list, service_id)
    --同服务只执行一次
    if self.services[service_id] then
        return
    end
    for _, cmd in pairs(command_list) do
        cmdline:register_command(cmd.name, cmd.args, cmd.desc, cmd.gm_type, service_id)
    end
    self.services[service_id] = true
    return SUCCESS
end

--执行gm, command：string
function AdminMgr:rpc_execute_command(command)
    local res = self:exec_command(command)
    return SUCCESS, res
end

--执行gm, message: table
function AdminMgr:rpc_execute_message(message)
    local res = self:exec_message(message)
    return SUCCESS, res
end

--http 回调
----------------------------------------------------------------------
--gm_page
function AdminMgr:on_gm_page(url, body, request)
    local ret_headers = { ["Access-Control-Allow-Origin"] = "*" }
    return self.http_server:build_response(200, gm_page, ret_headers)
end

--gm列表
function AdminMgr:on_gmlist(url, body, request)
    return cmdline:get_command_defines()
end

--后台GM调用，字符串格式
function AdminMgr:on_command(url, body, request)
    log_debug("[AdminMgr][on_command] body: %s", body)
    local cmd_req = json_decode(body)
    local data = strim(cmd_req.data)
    return self:exec_command(data)
end

--后台GM调用，table格式
function AdminMgr:on_message(url, body, request)
    log_debug("[AdminMgr][on_message] body: %s", body)
    local cmd_req     = json_decode(body)
    local data        = strim(cmd_req.data)
    local res         = self:exec_message(data)
    local ret_headers = { ["Access-Control-Allow-Origin"] = "*" }
    return self.http_server:build_response(200, res, ret_headers)
end

--monitor上报
function AdminMgr:on_monitor(url, body, request)
    log_debug("[AdminMgr][on_monitor] body: %s", body)
    local cmd_req               = json_decode(body)
    self.monitors[cmd_req.addr] = true
    return { code = 0 }
end

--monitor拉取
function AdminMgr:on_monitors(url, body, request)
    log_debug("[AdminMgr][on_monitors] body: %s", body)
    local monitors = {  }
    for addr in pairs(self.monitors) do
        monitors[#monitors + 1] = addr
    end
    return monitors
end

-------------------------------------------------------------------------
--后台GM执行，字符串格式
function AdminMgr:exec_command(command)
    local fmtargs, err = cmdline:parser_command(command)
    if not fmtargs then
        return { code = 1, msg = err }
    end
    return self:dispatch_command(fmtargs.args, fmtargs.type, fmtargs.service)
end

--后台GM执行，table格式
--message必须有name字段，作为cmd_name
function AdminMgr:exec_message(message)
    local fmtargs, err = cmdline:parser_data(message)
    if not fmtargs then
        return { code = 1, msg = err }
    end
    return self:dispatch_command(fmtargs.args, fmtargs.type, fmtargs.service)
end

--分发command
function AdminMgr:dispatch_command(cmd_args, gm_type, service)
    if gm_type == GMType.GLOBAL then
        return self:exec_global_cmd(service, tunpack(cmd_args))
    elseif gm_type == GMType.SYSTEM then
        return self:exec_system_cmd(service, tunpack(cmd_args))
    elseif gm_type == GMType.SERVICE then
        return self:exec_service_cmd(service, tunpack(cmd_args))
    elseif gm_type == GMType.DEV_OPS then
        return self:exec_global_cmd(service, tunpack(cmd_args))
    end
    return self:exec_player_cmd(tunpack(cmd_args))
end

--GLOBAL command
function AdminMgr:exec_global_cmd(service_id, cmd_name, ...)
    local ok, codeoe, res = router_mgr:call_random(service_id, "rpc_command_execute", cmd_name, ...)
    if not ok then
        log_err("[AdminMgr][exec_global_cmd] call_random(rpc_command_execute) failed! service_id=%s", service_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

--system command
function AdminMgr:exec_system_cmd(service_id, cmd_name, target_id, ...)
    local index           = guid_index(target_id)
    local hive_id         = smake_id(service_id, index)
    local ok, codeoe, res = router_mgr:call_target(hive_id, "rpc_command_execute", cmd_name, target_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_system_cmd] call_target(rpc_command_execute) failed! target_id=%s", target_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

--service command
function AdminMgr:exec_service_cmd(service_id, cmd_name, target_id, ...)
    local ok, codeoe, res = router_mgr:call_hash(service_id, target_id, "rpc_command_execute", cmd_name, target_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_service_cmd] call_target(rpc_command_execute) failed! target_id=%s", target_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

--player command
function AdminMgr:exec_player_cmd(cmd_name, player_id, ...)
    if player_id == 0 then
        local ok, codeoe, res = router_mgr:call_lobby_random("rpc_command_execute", cmd_name, player_id, ...)
        if not ok then
            log_err("[AdminMgr][exec_player_cmd] call_lobby_random(rpc_command_execute) failed! player_id=%s", player_id)
            return { code = 1, msg = codeoe }
        end
        return { code = codeoe, msg = res }
    end
    local ok, codeoe, res = online_agent:transfer_message(player_id, "rpc_command_execute", cmd_name, player_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_player_cmd] rpc_transfer_message(rpc_command_execute) failed! player_id=%s", player_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

hive.admin_mgr = AdminMgr()

return AdminMgr
