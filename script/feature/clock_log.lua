--计时器
local ltimer    = require("ltimer")
local lclock_ms = ltimer.clock_ms
local log_err   = logger.err

local ClockLog  = class()

function ClockLog:__init(name, cost)
    self.name     = name
    self.cost     = cost
    self.start_ms = lclock_ms()
end

function ClockLog:__defer()
    local cost_ms = lclock_ms() - self.start_ms
    if cost_ms > self.cost then
        log_err("[ClockLog][__defer] the %s,run cost:%s > %s,it maybe use up cpu !!!!!!", self.name, cost_ms, self.cost)
    end
end

return ClockLog
