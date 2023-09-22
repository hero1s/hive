local send_worker = hive.send_worker
local call_worker = hive.call_worker
local log_err     = logger.err
local TITLE       = hive.title
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
    if TITLE ~= self.service then
        return send_worker(self.service, rpc, ...)
    end
    log_err("[WorkerAgent][send] why send self:{}", rpc)
    return false, "can't send self!"
end

function WorkerAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return call_worker(self.service, rpc, ...)
    end
    log_err("[WorkerAgent][call] why call self:{}", rpc)
    return false, "can't call self!"
end

return WorkerAgent
