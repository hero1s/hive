--gm_agent.lua

local tunpack       = table.unpack
local log_info      = logger.info
local check_success = hive.success

local router_mgr    = hive.get("router_mgr")
local monitor       = hive.get("monitor")
local event_mgr     = hive.get("event_mgr")
local thread_mgr    = hive.get("thread_mgr")

local SUCCESS       = hive.enum("KernCode", "SUCCESS")
local LOGIC_FAILED  = hive.enum("KernCode", "LOGIC_FAILED")
local PeriodTime    = enum("PeriodTime")
local GMType        = enum("GMType")

local GMAgent       = singleton()
local prop          = property(GMAgent)
prop:reader("command_list", {})

function GMAgent:__init()
    --注册gm事件分发
    event_mgr:add_listener(self, "rpc_command_execute")
    -- 关注 gm服务 事件
    monitor:watch_service_ready(self, "admin")
end

--插入一条command
function GMAgent:insert_command(cmd_list, listener)
    if listener then
        for _, v in ipairs(cmd_list) do
            event_mgr:add_listener(listener, v.name)
        end
    end
    local default_groups = { "全局未分组", "玩家未分组", "服务未分组", "业务未分组" }
    for _, cmd in pairs(cmd_list) do
        if not cmd.gm_type then
            cmd.gm_type = GMType.PLAYER
        end
        if not cmd.group then
            cmd.group = default_groups[cmd.gm_type + 1]
        end
        self.command_list[cmd.name] = cmd
    end

    if monitor:exist_service("admin") then
        self:report_command()
    end
end

--执行一条command
--主要用于服务器内部执行GM指令
--command：字符串格式
function GMAgent:execute_command(command)
    local ok, code, res = router_mgr:call_admin_master("rpc_execute_command", command)
    if check_success(code, ok) then
        return ok, res
    end
    return false, res
end

--执行一条command
--主要用于服务器内部执行GM指令
--message：lua table格式
function GMAgent:execute_message(message)
    local ok, codeoe, res = router_mgr:call_admin_master("rpc_execute_message", message)
    if check_success(codeoe, ok) then
        return ok, res
    end
    return false, ok and res or codeoe
end

function GMAgent:report_command()
    local command_list = {}
    for _, cmd in pairs(self.command_list) do
        command_list[#command_list + 1] = cmd
    end
    local ok, code = router_mgr:call_admin_master("rpc_register_command", command_list, hive.service_id)
    if check_success(code, ok) then
        log_info("[GMAgent][report_command] success!")
        return true
    end
    return false
end

-- 通知执行GM指令
function GMAgent:rpc_command_execute(cmd_name, ...)
    log_info("[GMAgent][rpc_command_execute]->cmd_name:{},{}", cmd_name, { ... })
    local ok, res = tunpack(event_mgr:notify_listener(cmd_name, ...))
    return ok and SUCCESS or LOGIC_FAILED, res
end

-- GM服务已经ready
function GMAgent:on_service_ready(id, service_name)
    log_info("[GMAgent][on_service_ready]->id:{}, service_name:{}", id, service_name)
    -- 上报gm列表
    thread_mgr:success_call(PeriodTime.SECOND_10_MS, function()
        return self:report_command()
    end, PeriodTime.SECOND_10_MS)
end

hive.gm_agent = GMAgent()

return GMAgent
