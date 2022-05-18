-- cooling

local Cooling = class()
local prop    = property(Cooling)
prop:reader("begin_tick", 0)
prop:reader("end_tick", 0)
prop:accessor("status", 0)

--构造函数
function Cooling:__init()
    self.begin_tick = hive.now_ms
    self.end_tick   = hive.now_ms
end

function Cooling:get_cool_tick()
    local now_ms = hive.now_ms
    if self.end_tick > now_ms then
        return self.end_tick - now_ms
    end
    return 0
end

function Cooling:get_pass_tick()
    local now_ms = hive.now_ms
    if now_ms > self.begin_tick then
        return now_ms - self.begin_tick
    end
    return 0
end

function Cooling:get_total_tick()
    if self.end_tick > self.begin_tick then
        return self.end_tick - self.begin_tick
    end
    return 0
end

function Cooling:begin_cooling(tick)
    if tick < 0 then
        self.begin_tick = 0
        self.end_tick   = 0
        return false
    end
    self.begin_tick = hive.now_ms
    self.end_tick   = self.begin_tick + tick
    return true
end

function Cooling:is_time_out()
    return self:get_cool_tick() == 0
end

return Cooling
