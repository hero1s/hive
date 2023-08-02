--event_mgr.lua
local tinsert       = table.insert
local tunpack       = table.unpack

local thread_mgr    = hive.get("thread_mgr")

local Listener      = import("basic/listener.lua")

local EventMgr = singleton(Listener)
local prop = property(EventMgr)
prop:reader("fevent_set", {})       -- frame event set
prop:reader("sevent_set", {})       -- second event set
function EventMgr:__init()
end

function EventMgr:on_frame()
    local handlers = self.fevent_set
    self.fevent_set = {}
    for _, handler in pairs(handlers) do
        thread_mgr:fork(handler)
    end
end

function EventMgr:on_second()
    local handlers = self.sevent_set
    self.sevent_set = {}
    for _, handler in pairs(handlers) do
        thread_mgr:fork(handler)
    end
end

--延迟一帧
function EventMgr:fire_frame(event, ...)
    if type(event) == "function" then
        tinsert(self.fevent_set, event)
        return
    end
    local args = { ... }
    tinsert(self.fevent_set, function()
        self:notify_trigger(event, tunpack(args))
    end)
end

--延迟一秒
function EventMgr:fire_second(event, ...)
    if type(event) == "function" then
        tinsert(self.sevent_set, event)
        return
    end
    local args = { ... }
    tinsert(self.sevent_set, function()
        self:notify_trigger(event, tunpack(args))
    end)
end

-- export
hive.event_mgr = EventMgr()

return EventMgr