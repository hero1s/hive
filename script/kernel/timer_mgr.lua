--timer_mgr.lua
local ltimer          = require("ltimer")
local lcodec          = require("lcodec")
local log_err         = logger.err
local log_info        = logger.info
local ipairs          = ipairs
local tpack           = table.pack
local tunpack         = table.unpack
local new_guid        = lcodec.guid_new
local lclock_ms       = ltimer.clock_ms
local lnow_ms         = ltimer.now_ms
local lcron_next      = ltimer.cron_next
local ltinsert        = ltimer.insert
local ltupdate        = ltimer.update

--定时器精度，20ms
local TIMER_ACCURYACY = 20

local thread_mgr      = hive.get("thread_mgr")

local TimerMgr        = singleton()
local prop            = property(TimerMgr)
prop:reader("timers", {})
prop:reader("last_ms", 0)
prop:reader("escape_ms", 0)
function TimerMgr:__init()
    self.last_ms = lclock_ms()
end

function TimerMgr:trigger(handle, clock_ms)
    if handle.times > 0 then
        handle.times = handle.times - 1
    end
    --防止在定时器中阻塞
    handle.params[#handle.params] = clock_ms - handle.last
    thread_mgr:fork(handle.cb, tunpack(handle.params))
    --更新定时器数据
    if handle.times == 0 then
        self.timers[handle.timer_id] = nil
        return
    end
    --继续注册
    handle.last = clock_ms
    ltinsert(handle.timer_id, handle.period)
end

function TimerMgr:on_frame(clock_ms)
    local escape_ms = clock_ms - self.last_ms + self.escape_ms
    self.escape_ms  = escape_ms % TIMER_ACCURYACY
    self.last_ms    = clock_ms
    if escape_ms >= TIMER_ACCURYACY then
        local timers = ltupdate(escape_ms // TIMER_ACCURYACY)
        for _, timer_id in ipairs(timers or {}) do
            local handle = self.timers[timer_id]
            if handle then
                self:trigger(handle, clock_ms)
            end
        end
    end
end

function TimerMgr:once(period, cb, ...)
    return self:register(period, period, 1, cb, ...)
end

function TimerMgr:loop(period, cb, ...)
    return self:register(period, period, -1, cb, ...)
end

function TimerMgr:loop_interval(interval, period, cb, ...)
    return self:register(interval, period, -1, cb, ...)
end

function TimerMgr:cron(cex, cb, ...)
    local time, time_str = lcron_next(cex)
    if time < 0 then
        log_err("[TimerMgr][cron] the cron is error:[%s],[%s]", cex, time_str)
        return
    end
    log_info("[TimerMgr][cron] the cron next start:[%s],[%s]", cex, time_str)
    self:once((time - hive.now) * 1000, cb, ...)
end

function TimerMgr:register(interval, period, times, cb, ...)
    --生成id并注册
    local reg_ms   = lclock_ms()
    local timer_id = new_guid(period, interval)
    --矫正时间误差
    interval       = interval + (reg_ms - self.last_ms)
    ltinsert(timer_id, interval // TIMER_ACCURYACY)
    --包装回调参数
    local params          = tpack(...)
    params[#params + 1]   = 0
    --保存信息
    self.timers[timer_id] = {
        cb       = cb,
        last     = reg_ms,
        times    = times,
        params   = params,
        timer_id = timer_id,
        period   = period // TIMER_ACCURYACY
    }
    return timer_id
end

function TimerMgr:unregister(timer_id)
    if timer_id then
        self.timers[timer_id] = nil
    end
end

function TimerMgr:set_period(timer_id, period)
    local info = self.timers[timer_id]
    if info then
        info.period = period // TIMER_ACCURYACY
    end
end

function TimerMgr:clock_ms()
    return lclock_ms()
end

function TimerMgr:now_ms()
    return lnow_ms()
end

hive.timer_mgr = TimerMgr()

return TimerMgr
