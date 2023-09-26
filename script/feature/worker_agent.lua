local send_worker = hive.send_worker
local call_worker = hive.call_worker
local log_err     = logger.err
local TITLE       = hive.title
local hhash       = hive.hash
local scheduler   = hive.load("scheduler")
local sformat     = string.format

local WorkerAgent = class()
local prop        = property(WorkerAgent)
prop:reader("service", "")
prop:reader("thread_num", nil)

function WorkerAgent:__init()

end

function WorkerAgent:startup(path, thread_num)
    if scheduler then
        if thread_num and thread_num > 1 then
            self.thread_num = thread_num
            for i = 1, self.thread_num do
                scheduler:startup(sformat("%s_%d", self.service, i), path)
            end
        else
            scheduler:startup(self.service, path)
        end
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

function WorkerAgent:hash_service(hash_key)
    return sformat("%s_%d", self.service, hhash(hash_key, self.thread_num))
end

function WorkerAgent:send_hash(hash_key, rpc, ...)
    if scheduler then
        return scheduler:send(self:hash_service(hash_key), rpc, ...)
    end
    if TITLE ~= self.service then
        return send_worker(self:hash_service(hash_key), rpc, ...)
    end
    log_err("[WorkerAgent][send] why send self:{}", rpc)
    return false, "can't send self!"
end

function WorkerAgent:call_hash(hash_key, rpc, ...)
    if scheduler then
        return scheduler:call(self:hash_service(hash_key), rpc, ...)
    end
    if TITLE ~= self.service then
        return call_worker(self:hash_service(hash_key), rpc, ...)
    end
    log_err("[WorkerAgent][call] why call self:{}", rpc)
    return false, "can't call self!"
end

return WorkerAgent
