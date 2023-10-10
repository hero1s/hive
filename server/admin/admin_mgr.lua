--gm_mgr.lua
import("basic/cmdline.lua")
import("agent/online_agent.lua")

local gm_page       = nil
local HttpServer    = import("network/http_server.lua")
local tunpack       = table.unpack
local env_get       = environ.get
local log_err       = logger.err
local log_debug     = logger.debug
local readfile      = io_ext.readfile

local GMType        = enum("GMType")
local KernCode      = enum("KernCode")
local SUCCESS       = KernCode.SUCCESS
local check_success = hive.success
local cmdline       = hive.get("cmdline")
local event_mgr     = hive.get("event_mgr")
local router_mgr    = hive.get("router_mgr")
local online_agent  = hive.get("online_agent")
local update_mgr    = hive.get("update_mgr")

local AdminMgr      = singleton()
local prop          = property(AdminMgr)
prop:reader("http_server", nil)
prop:reader("deploy", "local")
prop:reader("services", {})

function AdminMgr:__init()
    --监听事件
    event_mgr:add_listener(self, "rpc_register_command")
    event_mgr:add_listener(self, "rpc_execute_command")
    event_mgr:add_listener(self, "rpc_execute_message")

    --创建HTTP服务器
    local server = HttpServer(env_get("HIVE_ADMIN_HTTP"))
    server:register_get("/", "on_gm_page", self)
    server:register_get("/gmlist", "on_gmlist", self)
    server:register_post("/command", "on_command", self)
    server:register_post("/message", "on_message", self)
    service.make_node(server:get_port())
    self.http_server = server
    --ip白名单
    local white_ips  = environ.table("HIVE_ADMIN_LIMIT_IP")
    local ips        = {}
    for i, ip in ipairs(white_ips) do
        ips[ip] = 1
    end
    if next(ips) then
        self.http_server:set_limit_ips(ips)
        log_debug("admin limit ips:{}", ips)
    end
    --用户密码
    self.user = environ.get("HIVE_ADMIN_USER", "admin")
    self.pwd  = environ.get("HIVE_ADMIN_PWD", "dsybs")

    --定时更新
    update_mgr:attach_minute(self)
end

--rpc请求
---------------------------------------------------------------------
--注册GM
function AdminMgr:rpc_register_command(command_list, service_id)
    --同服务只执行一次
    if self.services[service_id] then
        return SUCCESS
    end
    for _, cmd in pairs(command_list) do
        cmdline:register_command(cmd.name, cmd.args, cmd.desc, cmd.comment or "", cmd.gm_type, service_id, service.sid2name(service_id), cmd.group)
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

function AdminMgr:on_minute()
    gm_page = nil
end

--http 回调
----------------------------------------------------------------------
--gm_page
function AdminMgr:on_gm_page(url, querys, request)
    if not gm_page then
        local html_path = hive.import_file_dir("admin/admin_mgr.lua") .. "/gm_page.html"
        gm_page         = readfile(html_path)
        if environ.get("HTTP_MODE") == "https" then
            gm_page = gm_page:gsub("X%-UA%-Compatible", "Content-Security-Policy")
            gm_page = gm_page:gsub("IE=edge,chrome=1", "upgrade-insecure-requests")
        end
        if not gm_page then
            log_err("[AdminMgr][on_gm_page] load html faild:{}", html_path)
        end
    end
    local user = querys["user"]
    local pwd  = querys["pwd"]
    if user ~= self.user or pwd ~= self.pwd then
        return "this http request hasn't process!"
    end
    return gm_page, { ["Access-Control-Allow-Origin"] = "*" }
end

--gm列表
function AdminMgr:on_gmlist(url, querys)
    return cmdline:get_command_defines()
end

--后台GM调用，字符串格式
function AdminMgr:on_command(url, body)
    log_debug("[AdminMgr][on_command] body: {}", body)
    return self:exec_command(body.data)
end

--后台GM调用，table格式
function AdminMgr:on_message(url, body)
    log_debug("[AdminMgr][on_message] body: {}", body)
    return self:exec_message(body.data)
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
    end
    return self:exec_player_cmd(tunpack(cmd_args))
end

--GLOBAL command
function AdminMgr:exec_global_cmd(service_id, cmd_name, ...)
    local ok, codeoe, res = router_mgr:call_hash(service_id, service_id, "rpc_command_execute", cmd_name, ...)
    if not ok then
        log_err("[AdminMgr][exec_global_cmd] call_random(rpc_command_execute) failed! service_id={}", service_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

--system command
function AdminMgr:exec_system_cmd(service_id, cmd_name, target_id, ...)
    local ok, code, res = router_mgr:collect(service_id, "rpc_command_execute", cmd_name, target_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_system_cmd] call_target(rpc_command_execute) failed! target_id={}", target_id)
        return { code = 1, msg = code }
    end
    return { code = code, msg = res }
end

--service command
function AdminMgr:exec_service_cmd(service_id, cmd_name, target_id, ...)
    local ok, codeoe, res = router_mgr:call_hash(service_id, target_id, "rpc_command_execute", cmd_name, target_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_service_cmd] call_target(rpc_command_execute) failed! target_id={}", target_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

--player command
function AdminMgr:exec_player_cmd(cmd_name, player_id, ...)
    if player_id == 0 then
        local ok, codeoe, res = router_mgr:call_lobby_hash(player_id, "rpc_command_execute", cmd_name, player_id, ...)
        if not ok then
            log_err("[AdminMgr][exec_player_cmd] call_lobby_random(rpc_command_execute) failed! player_id={}", player_id)
            return { code = 1, msg = codeoe }
        end
        return { code = codeoe, msg = res }
    end
    local ok1, code, lobby_id = online_agent:query_player(player_id)
    if check_success(code, ok1) and lobby_id == 0 then
        --离线处理
        router_mgr:call_lobby_hash(player_id, "rpc_offline_player_gm", cmd_name, player_id, ...)
        return { code = SUCCESS, msg = "玩家不在线,已发送离线处理" }
    end
    local ok, codeoe, res = online_agent:call_lobby(player_id, "rpc_command_execute", cmd_name, player_id, ...)
    if not ok then
        log_err("[AdminMgr][exec_player_cmd] rpc_call_lobby(rpc_command_execute) failed! player_id={}", player_id)
        return { code = 1, msg = codeoe }
    end
    return { code = codeoe, msg = res }
end

hive.admin_mgr = AdminMgr()

return AdminMgr
