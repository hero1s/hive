--gm_agent.lua

local tunpack       = table.unpack
local log_info      = logger.info
local check_success = hive.success

local router_mgr    = hive.get("router_mgr")
local event_mgr     = hive.get("event_mgr")

local SUCCESS       = hive.enum("KernCode", "SUCCESS")
local LOGIC_FAILED  = hive.enum("KernCode", "LOGIC_FAILED")

local GMAgent = singleton()
local prop = property(GMAgent)
prop:accessor("command_list", {})

function GMAgent:__init()
    --注册gm事件分发
    event_mgr:add_listener(self, "rpc_command_execute")
    -- 关注 gm服务 事件
    router_mgr:watch_service_ready(self, "admin")
end

--插入一条command
function GMAgent:insert_command(command_list)
    for _, cmd in pairs(command_list) do
        self.command_list[cmd.name] = cmd
    end
end

--执行一条command
--主要用于服务器内部执行GM指令
--command：字符串格式
function GMAgent:execute_command(command)
    local ok, code, res = router_mgr:call_admin_master("rpc_execute_command", command)
    if ok and check_success(code) then
        return ok, res
    end
    return false, res
end

--执行一条command
--主要用于服务器内部执行GM指令
--message：lua table格式
function GMAgent:execute_message(message)
    local ok, codeoe, res = router_mgr:call_admin_master("rpc_execute_message", message)
    if ok and check_success(codeoe) then
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
    if ok and check_success(code) then
        log_info("[GMAgent][report_command] success!")
        return true
    end
end

-- 通知执行GM指令
function GMAgent:rpc_command_execute(cmd_name, ...)
    log_info("[GMAgent][rpc_command_execute]->cmd_name:%s", cmd_name)
    local ok, res = tunpack(event_mgr:notify_listener(cmd_name, ...))
    return ok and SUCCESS or LOGIC_FAILED, res
end

-- GM服务已经ready
function GMAgent:on_service_ready(id, service_name)
    log_info("[GMAgent][on_service_ready]->id:%s, service_name:%s", id, service_name)
    -- 上报gm列表
    self:report_command()
end

function GMAgent:on_inject(code_string)
    local func = load(code_string)
    func()
end

hive.gm_agent = GMAgent()

return GMAgent
