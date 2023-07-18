local tunpack     = table.unpack
local send_worker = hive.send_worker
local call_worker = hive.call_worker

local TITLE       = hive.title
local event_mgr   = hive.get("event_mgr")
local scheduler   = hive.load("scheduler")

local WorkerAgent = class()
local prop        = property(WorkerAgent)
prop:reader("service", "")

function WorkerAgent:__init()

end

function WorkerAgent:startup(path)
    if scheduler then
        --启动系统线程
        scheduler:startup(self.service, path)
    end
end

function WorkerAgent:send(rpc, ...)
    if scheduler then
        return scheduler:send(self.service, rpc, ...)
    end
    logger.debug("----%s,%s", TITLE, self.service)
    if TITLE ~= self.service then
        return send_worker(self.service, rpc, ...)
    end
    event_mgr:notify_listener(rpc, ...)
end

function WorkerAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return call_worker(self.service, rpc, ...)
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    return tunpack(rpc_datas)
end

return WorkerAgent
