--countor.lua
local log_info   = logger.info
local cut_tail   = math_ext.cut_tail

local timer_mgr  = hive.get("timer_mgr")
local update_mgr = hive.get("update_mgr")

local SECOND_MS  = hive.enum("PeriodTime", "SECOND_MS")
local MINUTE_MS  = hive.enum("PeriodTime", "MINUTE_MS")

local Counter    = class()
local prop       = property(Counter)
prop:reader("title", "")
prop:reader("time", 0)          --采样次数
prop:reader("min", 0)           --统计周期最小值
prop:reader("max", 0)           --统计周期最大值
prop:reader("total", 0)         --统计周期总值
prop:reader("count", 0)         --计数
prop:accessor("counter", nil)   --计数器

function Counter:__init(title)
    self.title = title
    --统计周期更新
    update_mgr:attach_minute(self)
end

--设置采样周期
function Counter:sampling(period, counter)
    self.counter   = counter
    local sampling = period or SECOND_MS
    self.time      = MINUTE_MS / sampling
    timer_mgr:loop(sampling, function()
        self:on_update()
    end)
end

--采样更新数据
function Counter:on_update()
    local count = self.count
    if self.counter then
        count = self.counter()
        if count > self.max then
            self.max = count
        end
        if count < self.min then
            self.min = count
        end
    end
    self.total = self.total + count
    self.count = 0
end

--输出统计
function Counter:on_minute()
    if self.time > 0 then
        local avg = cut_tail(self.total / self.time, 1)
        log_info("[Counter][on_minute] last minute %s count => total:%s, avg:%s range:%s-%s!", self.title, self.total, avg, self.min, self.max)
        self.total = 0
        self.max   = 0
        self.min   = 0
    else
        log_info("[Counter][on_minute] last minute %s count => cur:%s range:%s-%s!", self.title, self.count, self.min, self.max)
        self.max = self.count
        self.min = self.count
    end
end

function Counter:count_increase()
    self.count = self.count + 1
    if self.count > self.max then
        self.max = self.count
    end
end

function Counter:count_reduce()
    if self.count > 0 then
        self.count = self.count - 1
        if self.count < self.min then
            self.min = self.count
        end
    end
end

function Counter:get_info()
    return self.count, self.max, self.min
end

return Counter
