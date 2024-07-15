--计时器
local ltimer    = require("ltimer")
local lclock_ms = ltimer.clock_ms
local log_err   = logger.err

local ClockLog  = class()

function ClockLog:__init(cost, ext, thread)
    self.source   = hive.where_call(thread or 4)
    self.ext      = ext
    self.cost     = cost
    self.start_ms = lclock_ms()
end

function ClockLog:__defer()
    local cost_ms = lclock_ms() - self.start_ms
    if cost_ms > self.cost then
        log_err("[ClockLog][__defer] the [%s][%s],run cost:%s > %s,it maybe use up cpu !!!!!!", self.source, self.ext, cost_ms, self.cost)
    end
end

return ClockLog
