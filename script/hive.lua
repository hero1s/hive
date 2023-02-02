--hive.lua
local ltimer     = require("ltimer")
local lcodec     = require("lcodec")
local lclock_ms  = ltimer.clock_ms
local guid_new   = lcodec.guid_new

local odate      = os.date
local log_err    = logger.err
local log_warn   = logger.warn
local sformat    = string.format
local tpack      = table.pack
local tunpack    = table.unpack
local dgetinfo   = debug.getinfo
local dsethook   = debug.sethook
local dtraceback = debug.traceback

--函数装饰器: 保护性的调用指定函数,如果出错则写日志
--主要用于一些C回调函数,它们本身不写错误日志
--通过这个装饰器,方便查错
function hive.xpcall(func, format, ...)
    local ok, err = xpcall(func, dtraceback, ...)
    if not ok then
        log_err(sformat(format, err))
    end
end

function hive.xpcall_ret(func, format, ...)
    local result = tpack(xpcall(func, dtraceback, ...))
    if not result[1] then
        log_err(sformat(format, result[2]))
    end
    return tunpack(result)
end

function hive.try_call(func, time, ...)
    while time > 0 do
        time = time - 1
        if func(...) then
            return true
        end
    end
    return false
end

function hive.where_call()
    local info = dgetinfo(3, "nSl")
    return sformat("[%s:%d]", info.short_src, info.currentline or 0)
end

-- 启动死循环监控
function hive.check_endless_loop()
    log_warn("open check_endless_loop will degrade performance!")
    local debug_hook = function()
        local now = lclock_ms()
        if now - hive.clock_ms >= 10000 then
            log_err(sformat("check_endless_loop:%s", dtraceback()))
        end
    end
    dsethook(debug_hook, "l")
end

--快速获取enum
local function henum(ename, ekey)
    local eobj = enum(ename)
    if not eobj then
        local info = dgetinfo(2, "S")
        log_err(sformat("[hive][enum] %s not initial! source(%s:%s)", ename, info.short_src, info.linedefined))
        return
    end
    local eval = eobj[ekey]
    if not eval then
        local info = dgetinfo(2, "S")
        log_err(sformat("[hive][enum] %s.%s not defined! source(%s:%s)", ename, ekey, info.short_src, info.linedefined))
        return
    end
    return eval
end

hive.enum     = henum
local FAILED  = henum("KernCode", "FAILED")
local SUCCESS = henum("KernCode", "SUCCESS")
local DAY_S   = henum("PeriodTime", "DAY_S")
local HOUR_S  = henum("PeriodTime", "HOUR_S")

function hive.success(code, ok)
    if ok == nil then
        return code == SUCCESS
    end
    return ok and code == SUCCESS
end

function hive.failed(code, ok, def_code)
    if ok == nil then
        return code ~= SUCCESS
    end
    return not ok or code ~= SUCCESS, ok and code or (def_code or FAILED)
end

---获取utc时间戳
local utc_diff_time = nil
function hive.utc_time(time)
    if not time or time <= 0 then
        time = hive.now
    end
    if not utc_diff_time then
        local nowt      = odate("*t", time)
        local utct      = odate("!*t", time)
        local diff_hour = nowt.hour - utct.hour
        if diff_hour < 0 then
            diff_hour = diff_hour + 24
        end
        utc_diff_time = diff_hour * HOUR_S
    end
    return time + utc_diff_time
end

--获取一个类型的时间版本号
function hive.edition(period, time, offset)
    local edition = 0
    if not time or time <= 0 then
        time = hive.now
    end
    time    = time - (offset or 0)
    local t = odate("*t", time)
    if period == "hour" then
        edition = time // HOUR_S
    elseif period == "day" then
        edition = time // DAY_S
    elseif period == "week" then
        --19700101是星期四，周日为每周第一天(游戏内周一为每周的第一天)
        edition = ((time // DAY_S) + 3) // 7
    elseif period == "month" then
        edition = t.year * 100 + t.month
    elseif period == "year" then
        edition = t.year
    end
    return edition
end

--获取UTC的时间版本号
function hive.edition_utc(period, time, offset)
    local utime = hive.utc_time(time)
    return hive.edition(period, utime, offset)
end

local ServiceStatus_RUN = henum("ServiceStatus", "RUN")

function hive.is_runing()
    return hive.service_status == ServiceStatus_RUN
end

function hive.new_guid()
    return guid_new(hive.service_id, hive.index)
end