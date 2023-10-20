local os                       = os

---@class tm
---@field public year integer
---@field public month integer @[1,12]
---@field public day integer @[1,31]
---@field public hour integer
---@field public min integer
---@field public sec integer
---@field public wday integer @[0,6] 0 is sunday
---@field public yday integer @[1,366]
---@field public isdst integer


local WEEK<const>              = 7
local DAYS_IN_MONTH<const>     = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local DAYS_BEFORE_MONTH<const> = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

--- "year -> 1 if leap year, else 0."
local function is_leap(year)
    return (year % 4 == 0 and (year % 100 ~= 0 or year % 400 ~= 0))
end

--- year, month -> number of days in that month in that year.
local function days_in_month(year, month)
    assert(1 <= month and month <= 12, tostring(month))
    if month == 2 and is_leap(year) then
        return 29
    end
    return DAYS_IN_MONTH[month]
end

--- year -> number of days before January 1st of year.
local function days_before_year(year)
    local y = year - 1
    return y * 365 + y // 4 - y // 100 + y // 400
end

--- year, month -> number of days in year preceding first day of month.
local function days_before_month(year, month)
    assert(1 <= month and month <= 12, 'month must be in 1..12')
    return DAYS_BEFORE_MONTH[month] + ((month > 2 and is_leap(year)) and 1 or 0)
end

--- year, month, day -> ordinal, considering 01-Jan-0001 as day 1.
local function ymd2ord(year, month, day)
    assert(1 <= month and month <= 12, 'month must be in 1..12')
    local dim = days_in_month(year, month)
    assert(1 <= day and day <= dim, 'day must be in 1..' .. dim)
    return (days_before_year(year) +
            days_before_month(year, month) +
            day)
end

--- # Helper to calculate the day number of the Monday starting week 1
--- # XXX This could be done more efficiently
local function isoweek1monday(year)
    local firstday     = ymd2ord(year, 1, 1)
    local firstweekday = (firstday + 6) % WEEK  --- See weekday() above
    local week1monday  = firstday - firstweekday
    if firstweekday > 3 then
        week1monday = week1monday + WEEK
    end
    return week1monday
end

datetime_ext = _ENV.datetime_ext or {}

datetime_ext.SECONDS_ONE_DAY    = 86400
datetime_ext.SECONDS_ONE_HOUR   = 3600
datetime_ext.SECONDS_ONE_MINUTE = 60

---@param t integer @POSIX timestamp
---@return integer,integer,integer @ year, week number, and weekday
function datetime_ext.isocalendar(t)
    local tm          = os.date("*t", t or hive.now)
    local year        = tm.year
    local week1monday = isoweek1monday(year)
    local today       = ymd2ord(year, tm.month, tm.day)
    --Internally, week and day have origin 0
    local week, day   = (today - week1monday) // 7, (today - week1monday) % 7
    if week < 0 then
        year        = year - 1
        week1monday = isoweek1monday(year)
        week, day   = (today - week1monday) // 7, (today - week1monday) % 7
    elseif week >= 52 then
        if today >= isoweek1monday(year + 1) then
            year = year + 1
            week = 0
        end
    end
    return year, week + 1, day + 1
end

---@param time integer @POSIX timestamp
---@return tm
function datetime_ext.localtime(time)
    return os.date("*t", time)
end

function datetime_ext.time_str(timestamp)
    return os.date("%Y/%m/%d %H:%M:%S",timestamp)
end

---Return POSIX timestamp at today's 00:00:00
---@param time integer @POSIX timestamp
function datetime_ext.dailytime(time)
    local tm = os.date("*t", time)
    if tm.year == 1970 and tm.month == 1 and tm.day == 1 then
        if tm.hour < hive.timezone then
            return 0
        end
    end
    tm.hour = 0
    tm.min  = 0
    tm.sec  = 0
    return os.time(tm)
end

---Return days from ordinal, considering 01-Jan-0001 as day 1
---@param time integer @POSIX timestamp. if nil will use current time
---@return integer
function datetime_ext.localday(time)
    local tm = os.date("*t", time or hive.now)
    return ymd2ord(tm.year, tm.month, tm.day)
end

---@param time integer @POSIX timestamp.
---@return boolean
function datetime_ext.is_leap_year(time)
    local y = os.date("*t", time).year
    return (y % 4) == 0 and ((y % 100) ~= 0 or (y % 400) == 0);
end

function datetime_ext.is_same_day(time1, time2)
    return datetime_ext.localday(time1) == datetime_ext.localday(time2);
end

function datetime_ext.is_birthday(time1, time2)
    local tm1 = os.date("*t", time1)
    local tm2 = os.date("*t", time2 or hive.now)
    return tm1.month == tm2.month and tm1.day == tm2.day
end

function datetime_ext.is_same_week(time1, time2)
    local year1, yweek1, _ = datetime_ext.isocalendar(time1)
    local year2, yweek2, _ = datetime_ext.isocalendar(time2)
    return year1 == year2 and yweek1 == yweek2
end

function datetime_ext.is_same_month(time1, time2)
    local tm1 = os.date("*t", time1)
    local tm2 = os.date("*t", time2)
    return tm1.year == tm2.year and tm1.month == tm2.month
end

---Get diff of days, always >= 0
function datetime_ext.past_day(time1, time2)
    local d1 = datetime_ext.localday(time1);
    local d2 = datetime_ext.localday(time2);
    if d1 > d2 then
        return d1 - d2
    else
        return d2 - d1
    end
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
    tm = tm or hive.now
    local week_day = tonumber(os.date("%w", tm))
    if week_day == 0 then
        week_day = 7
    end
    return week_day
end
