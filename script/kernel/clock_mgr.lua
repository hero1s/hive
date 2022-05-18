--clock_mgr.lua
local lcrypt    = require("lcrypt")

local new_guid  = lcrypt.guid_new

local ClockMgr = singleton()
local prop = property(ClockMgr)
prop:reader("clocks", {})
function ClockMgr:__init()
end

--检查闹钟
function ClockMgr:check(clock_id, now_ms)
    local clock = self.clocks[clock_id]
    if clock then
        if now_ms >= clock.next_ms then
            local period = clock.period
            local clock_ms = now_ms - clock.last_ms
            local count = (now_ms - clock.start_ms) // period
            --循环次数满，删除闹钟
            if clock.cycle > 0 and count >= clock.cycle then
                self.clocks[clock_id] = nil
            end
            --未超过一个周期补偿，超过则忽略
            clock.next_ms = (now_ms + period) - (now_ms % period)
            clock.last_ms = now_ms
            clock.count = count
            return clock_ms, count
        end
    end
end

--添加周期闹钟
--period: 周期
--now_ms: 当前时间
--cycle: 循环次数，不传一直循环
--timestamp: 基准时间戳，用于在整点触发的闹钟(可选参数)
function ClockMgr:alarm(period, now_ms, cycle, timestamp)
    --生成id并注册
    local clock_id = new_guid(period, period)
    self.clocks[clock_id] = {
        count = 0,
        period = period,
        last_ms = now_ms,
        start_ms = now_ms,
        cycle = cycle or - 1,
        next_ms = now_ms + period
    }
    if timestamp then
        if timestamp < now_ms then
            timestamp = now_ms + period - (now_ms % period)
        end
        self.next_ms = timestamp
    end
    return clock_id
end

--关闭闹钟
function ClockMgr:close(clock_id)
    self.clocks[clock_id] = nil
end

function ClockMgr:on_quit()
    self.clocks = {}
end

hive.clock_mgr = ClockMgr()

return ClockMgr
