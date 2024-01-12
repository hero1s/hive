local os     = os

datetime_ext = _ENV.datetime_ext or {}

---@param time integer @POSIX timestamp
---@return tm
function datetime_ext.localtime(time)
    return os.date("*t", time)
end

function datetime_ext.time_str(timestamp)
    return os.date("%Y/%m/%d %H:%M:%S", timestamp)
end

---Return POSIX timestamp at today's 00:00:00
---@param time integer @POSIX timestamp
function datetime_ext.dailytime(time)
    return timer.day_begin_time(time or hive.now)
end

function datetime_ext.localday(time)
    return timer.local_day(time or hive.now)
end

function datetime_ext.is_same_day(time1, time2)
    return timer.diff_day(time1, time2) == 0
end

---Get diff of days, always >= 0
function datetime_ext.past_day(time1, time2)
    return math.abs(timer.diff_day(time1, time2))
end

---Make today's some time
function datetime_ext.make_hourly_time(time, hour, min, sec)
    local tm = os.date("*t", time or hive.now)
    if tm.year == 1970 and tm.month == 1 and tm.day == 1 then
        if hour < hive.timezone then
            return 0
        end
    end
    tm.hour = hour
    tm.min  = min
    tm.sec  = sec
    return os.time(tm)
end

---@param strtime string @ "2020/09/04 20:28:20"
---@return tm
function datetime_ext.parse(strtime)
    local rep = "return {year=%1,month=%2,day=%3,hour=%4,min=%5,sec=%6}"
    local res = string.gsub(strtime, "(%d+)[/-](%d+)[/-](%d+) (%d+):(%d+):(%d+)", rep)
    assert(res, "parse time format invalid " .. strtime)
    return load(res)()
end

function datetime_ext.make_time(tm)
    tm = {
        year  = tm.year,
        month = tm.month,
        day   = tm.day,
        hour  = tm.hour,
        min   = tm.min,
        sec   = tm.sec,
        isdst = os.date("*t", hive.now).isdst
    }
    return os.time(tm)
end

-- 获取当前是星期几，其中星期天为7
function datetime_ext.week_day(tm)
    tm             = tm or hive.now
    local week_day = tonumber(os.date("%w", tm))
    if week_day == 0 then
        week_day = 7
    end
    return week_day
end
