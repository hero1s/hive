local log_debug = logger.debug
local timer_mgr = hive.get("timer_mgr")

local TimerObj  = class()
local prop      = property(TimerObj)
prop:reader("timers", {})        --定时器任务
function TimerObj:__init()
end

function TimerObj:add_timer(delay, interval, callback, name)
    if type(callback) ~= "function" then
        callback = function()
            self[callback](self)
        end
    end
    local timer_id        = timer_mgr:loop_interval(delay, interval, callback)
    self.timers[timer_id] = name or true
    return timer_id
end

function TimerObj:remove_timer(timer_id)
    if self.timers[timer_id] then
        timer_mgr:unregister(timer_id)
        self.timers[timer_id] = nil
        return true
    end
    return false
end

function TimerObj:clear_timer()
    for timer_id, _ in pairs(self.timers) do
        timer_mgr:unregister(timer_id)
    end
    log_debug("[TimerObj][clear_timer] {}", self.timers)
    self.timers = {}
end

return TimerObj