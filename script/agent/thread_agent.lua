local tunpack     = table.unpack
local send_worker = hive.send_worker
local call_worker = hive.call_worker

local TITLE       = hive.title
local event_mgr   = hive.get("event_mgr")
local scheduler   = hive.load("scheduler")

local ThreadAgent = class()
local prop        = property(ThreadAgent)
prop:reader("service", "")

function ThreadAgent:__init()

end

function ThreadAgent:startup(service, path)
    self.service = service
    if scheduler then
        --启动系统线程
        scheduler:startup(self.service, path)
    end
end

function ThreadAgent:send(rpc, ...)
    if scheduler then
        return scheduler:send(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return send_worker(self.service, rpc, ...)
    end
    event_mgr:notify_listener(rpc, ...)
end

function ThreadAgent:call(rpc, ...)
    if scheduler then
        return scheduler:call(self.service, rpc, ...)
    end
    if TITLE ~= self.service then
        return call_worker(self.service, rpc, ...)
    end
    local rpc_datas = event_mgr:notify_listener(rpc, ...)
    return tunpack(rpc_datas)
end

return ThreadAgent
