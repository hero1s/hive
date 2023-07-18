local thread      = import("feature/worker_agent.lua")
local SystemAgent = singleton(thread)
function SystemAgent:__init()
    self.service = "system"
    self:startup("worker.system")
end

--执行code
function SystemAgent:call_code(code_str, sync)
    if sync then
        return self:call("rpc_execute_code", code_str)
    end
    self:send("rpc_execute_code", code_str)
end

--执行shell
function SystemAgent:call_shell(cmd, sync)
    if sync then
        return self:call("rpc_execute_shell", cmd)
    end
    self:send("rpc_execute_shell", cmd)
end

hive.system_agent = SystemAgent()

return SystemAgent
