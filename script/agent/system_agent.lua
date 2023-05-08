--proxy_agent.lua
local tunpack     = table.unpack
local send_worker = hive.send_worker
local call_worker = hive.call_worker

local WTITLE      = hive.worker_title
local event_mgr   = hive.get("event_mgr")
local scheduler   = hive.load("scheduler")

local SystemAgent = singleton()
local prop        = property(SystemAgent)
prop:reader("service", "system")

function SystemAgent:__init()
    if scheduler then
        --启动系统线程
        scheduler:startup(self.service, "worker.system")
    end
end

--执行shell
function SystemAgent:call_shell(cmd, sync)
    if sync then
        return self:call("rpc_execute_shell", cmd)
    end
    self:send("rpc_execute_shell", cmd)
end

function SystemAgent:send(rpc, ...)
    if scheduler then
        return scheduler:send(self.service, rpc, ...)
    end
    if WTITLE ~= self.service then
        return send_worker(self.service, rpc, ...)
    end
    event_mgr:notify_listener(rpc, ...)
end

function SystemAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service, rpc, ...)
    end
    if WTITLE ~= self.service then
        return call_worker(self.service, rpc, ...)
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    return tunpack(rpc_datas)
end

hive.system_agent = SystemAgent()

return SystemAgent
