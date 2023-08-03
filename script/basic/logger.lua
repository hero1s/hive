--logger.lua
--logger功能支持
local llog        = require("lualog")
local lstdfs      = require("lstdfs")
local lcodec      = require("lcodec")
local pcall       = pcall
local pairs       = pairs
local sformat     = string.format
local sfind       = string.find
local ssub        = string.sub
local dgetinfo    = debug.getinfo
local tpack       = table.pack
local tunpack     = table.unpack
local fsstem      = lstdfs.stem
local serialize   = lcodec.serialize
local lwarn       = llog.warn
local lfilter     = llog.filter

local LOG_LEVEL   = llog.LOG_LEVEL

logger            = {}
logfeature        = {}
local title       = hive.title
local monitors    = _ENV.monitors or {}
local dispatching = false
local logshow     = 0
local log_lvl     = 1

function logger.init()
    --配置日志信息
    local service_name, index = hive.service_name, hive.index
    local path                = environ.get("HIVE_LOG_PATH", "./logs/")
    local rolltype            = environ.number("HIVE_LOG_ROLL", 0)
    local log_size            = environ.number("HIVE_LOG_SIZE", 50 * 1024 * 1024)
    local maxdays             = environ.number("HIVE_LOG_DAYS", 7)
    logshow                   = environ.number("HIVE_LOG_SHOW", 0)
    log_lvl                   = environ.number("HIVE_LOG_LVL", 1)

    llog.set_max_logsize(log_size)
    llog.set_clean_time(maxdays * 24 * 3600)
    llog.option(path, service_name, index, rolltype);
    --设置日志过滤
    logger.filter(log_lvl)
    --添加输出目标
    llog.add_dest(service_name);
    --错误日志备份
    llog.add_lvl_dest(LOG_LEVEL.ERROR)
end

function logger.add_monitor(monitor, lvl)
    monitors[monitor] = lvl
end

function logger.remove_monitor(monitor)
    monitors[monitor] = nil
end

function logger.filter(level)
    for lvl = LOG_LEVEL.TRACE, LOG_LEVEL.FATAL do
        --llog.filter(level, on/off)
        lfilter(lvl, lvl >= level)
    end
end

local function logger_output(feature, notify, lvl, lvl_name, fmt, log_conf, ...)
    if lvl < log_lvl then
        return false
    end
    local content
    local lvl_func, extend, swline, max_depth, max_len = tunpack(log_conf)
    if extend then
        local args = tpack(...)
        for i, arg in pairs(args) do
            if type(arg) == "table" then
                args[i] = serialize(arg, swline and 1 or 0, max_depth, max_len)
            end
        end
        content = sformat(fmt, tunpack(args, 1, args.n))
    else
        content = sformat(fmt, ...)
    end
    lvl_func(content, title, feature)
    if notify and not dispatching then
        --防止重入
        dispatching = true
        for monitor, mlvl in pairs(monitors) do
            if lvl >= mlvl then
                monitor:dispatch_log(content, lvl_name)
            end
        end
        dispatching = false
    end
end

local function trim_src(short_src)
    if short_src == nil then
        return ""
    end

    local _, j = sfind(short_src, "%.%./")
    if j == nil then
        return short_src
    end

    return ssub(short_src, j + 1)
end

local LOG_LEVEL_OPTIONS = {
    --lvl_func,    extend,  swline, max_depth
    [LOG_LEVEL.TRACE] = { "trace", { llog.trace, true, false, 12, 4096 } },
    [LOG_LEVEL.DEBUG] = { "debug", { llog.debug, true, false, 8, 4096 } },
    [LOG_LEVEL.INFO]  = { "info", { llog.info, false, false, 0, 4096 } },
    [LOG_LEVEL.WARN]  = { "warn", { llog.warn, true, false, 8, 4096 } },
    [LOG_LEVEL.ERROR] = { "err", { llog.error, true, false, 8, 4096 } },
    [LOG_LEVEL.FATAL] = { "fatal", { llog.fatal, true, true, 8, 4096 } }
}
for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logger[lvl_name]         = function(fmt, ...)
        if logshow == 1 then
            local info = dgetinfo(2, "nSl")
            fmt        = sformat("[%s:%d(%s)]", trim_src(info.short_src), info.currentline or 0, info.name or "") .. fmt
        end
        local ok, res = pcall(logger_output, "", true, lvl, lvl_name, fmt, log_conf, ...)
        if not ok then
            local info = dgetinfo(2, "S")
            lwarn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
            return false
        end
        return res
    end
end

for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logfeature[lvl_name]     = function(feature, path, prefix, def)
        if not feature then
            local info = dgetinfo(2, "S")
            feature    = fsstem(info.short_src)
        end
        llog.add_dest(feature, path)
        llog.ignore_prefix(feature, prefix)
        llog.ignore_def(feature, def)
        return function(fmt, ...)
            local ok, res = pcall(logger_output, feature, false, lvl, lvl_name, fmt, log_conf, ...)
            if not ok then
                local info = dgetinfo(2, "S")
                lwarn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
                return false
            end
            return res
        end
    end
end
