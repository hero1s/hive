--hive.lua
local guid_new     = codec.guid_new
local hash_code    = codec.hash_code
local odate        = os.date
local log_err      = logger.err
local dgetinfo     = debug.getinfo
local setmetatable = setmetatable

function hive.get(name)
    local global_obj = hive[name]
    if not global_obj then
        local info = dgetinfo(2, "S")
        log_err("[hive][get] {} not initial! source({}:{})", name, info.short_src, info.linedefined)
        return
    end
    return global_obj
end

--快速获取enum
function hive.enum(ename, ekey)
    local eobj = enum(ename)
    if not eobj then
        local info = dgetinfo(2, "S")
        log_err("[hive][enum] {} not initial! source({}:{})", ename, info.short_src, info.linedefined)
        return
    end
    local eval = eobj[ekey]
    if not eval then
        local info = dgetinfo(2, "S")
        log_err("[hive][enum] {}.{} not defined! source({}:{})", ename, ekey, info.short_src, info.linedefined)
        return
    end
    return eval
end

local FAILED  = hive.enum("KernCode", "FAILED")
local SUCCESS = hive.enum("KernCode", "SUCCESS")
local DAY_S   = hive.enum("PeriodTime", "DAY_S")
local HOUR_S  = hive.enum("PeriodTime", "HOUR_S")

function hive.success(code, ok)
    if ok == nil then
        return code == SUCCESS
    end
    return ok and code == SUCCESS
end

function hive.failed(code, ok, def_code)
    if ok == nil then
        return code ~= SUCCESS, code or (def_code or FAILED)
    end
    return not ok or code ~= SUCCESS, code or (def_code or FAILED)
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

function hive.is_linux()
    return hive.platform == "linux"
end

function hive.new_guid()
    return guid_new(hive.service_id, hive.index)
end

function hive.hash(key, mod)
    return hash_code(key, mod)
end

function hive.defer(handler)
    return setmetatable({}, { __close = handler })
end

--创建普通计数器
function hive.make_counter(title, warn_avg)
    local Counter = import("feature/counter.lua")
    return Counter(title, warn_avg)
end

--创建采样计数器
function hive.make_sampling(title, period, warn_avg)
    local Counter = import("feature/counter.lua")
    local counter = Counter(title, warn_avg)
    counter:sampling(period)
    return counter
end

--创建管道
function hive.make_channel(title, timeout)
    local Channel = import("feature/channel.lua")
    return Channel(title, timeout or 1000)
end

--创建存储对象
function hive.make_store(sheet, primary_key, primary_id, cache)
    local Store = import("store/store.lua")
    return Store(sheet, primary_key, primary_id, cache)
end

--注册消息
function hive.register_cmd_listener(doer, cmd_id, callback)
    local protobuf_mgr = hive.get("protobuf_mgr")
    protobuf_mgr:register(doer, cmd_id, callback)
end

function hive.make_clock(cost, ext)
    local ClockLog = import("feature/clock_log.lua")
    return ClockLog(cost, ext, 5)
end

function hive.make_limiter(name, warn_size, refuse_size, qps_warn)
    local Limiter = import("feature/limiter.lua")
    return Limiter(name, warn_size, refuse_size, qps_warn)
end

function hive.make_timer()
    local Timer = import("feature/timer.lua")
    return Timer()
end