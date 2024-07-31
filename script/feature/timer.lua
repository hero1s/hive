--timer.lua

local timer_mgr = hive.get("timer_mgr")

local Timer     = class()
local prop      = property(Timer)
prop:reader("timer_id", nil)

function Timer:__init()
end

function Timer:__release()
    self:unregister()
end

function Timer:unregister()
    if self.timer_id then
        timer_mgr:unregister(self.timer_id)
        self.timer_id = nil
    end
end

function Timer:once(period, cb, ...)
    self:unregister()
    self.timer_id = timer_mgr:register(period, period, 1, cb, ...)
end

function Timer:loop(period, cb, ...)
    self:unregister()
    self.timer_id = timer_mgr:register(period, period, -1, cb, ...)
end

function Timer:register(interval, period, times, cb, ...)
    self:unregister()
    self.timer_id = timer_mgr:register(interval, period, times, cb, ...)
end

function Timer:set_period(period)
    if self.timer_id then
        timer_mgr:set_period(self.timer_id, period)
    end
end

return Timer
