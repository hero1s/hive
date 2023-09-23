--logger.lua
--logger功能支持
local pcall       = pcall
local pairs       = pairs
local sformat     = string.format
local dgetinfo    = debug.getinfo
local tunpack     = table.unpack
local fsstem      = stdfs.stem
local lprint      = log.print
local lfilter     = log.filter

local LOG_LEVEL   = log.LOG_LEVEL

logger            = {}
logfeature        = {}
local title       = hive.title
local monitors    = _ENV.monitors or {}
local log_lvl     = 1
local dispatching = false

function logger.init()
    --配置日志信息
    local service_name, index = hive.service_name, hive.index
    local path                = environ.get("HIVE_LOG_PATH", "./logs/")
    local rolltype            = environ.number("HIVE_LOG_ROLL", 0)
    local log_size            = environ.number("HIVE_LOG_SIZE", 50 * 1024 * 1024)
    local maxdays             = environ.number("HIVE_LOG_DAYS", 7)
    log_lvl                   = environ.number("HIVE_LOG_LVL", 1)

    log.set_max_logsize(log_size)
    log.set_clean_time(maxdays * 24 * 3600)
    log.option(path, service_name, index, rolltype);
    --设置日志过滤
    logger.filter(log_lvl)
    --添加输出目标
    log.add_dest(service_name);
    --错误日志备份
    log.add_lvl_dest(LOG_LEVEL.ERROR)
end

function logger.add_monitor(monitor, lvl)
    monitors[monitor] = lvl
end

function logger.remove_monitor(monitor)
    monitors[monitor] = nil
end

function logger.filter(level)
    for lvl = LOG_LEVEL.TRACE, LOG_LEVEL.FATAL do
        --log.filter(level, on/off)
        lfilter(lvl, lvl >= level)
    end
end

local function logger_format(flag, feature, lvl, lvl_name, fmt, ...)
    local ok, msg = pcall(sformat, fmt, ...)
    if not ok then
        local info = dgetinfo(4, "S")
        local wfmt = "[logger][{}] format failed: {}, source({}:{})"
        lprint(LOG_LEVEL.WARN, 0, title, feature, wfmt, lvl_name, msg, info.short_src, info.linedefined)
        return
    end
    lprint(lvl, flag, title, feature, msg)
end

local function logger_output(flag, feature, lvl, lvl_name, fmt, ...)
    if lvl < log_lvl then
        return
    end
    if not fmt:find("{") then
        return logger_format(flag, feature, lvl, lvl_name, fmt, ...)
    end
    local ok, msg = pcall(lprint, lvl, flag, title, feature, fmt, ...)
    if not ok then
        local info = dgetinfo(3, "S")
        local wfmt = "[logger][{}] format failed: {}, source({}:{})"
        lprint(LOG_LEVEL.WARN, 0, title, feature, wfmt, lvl_name, msg, info.short_src, info.linedefined)
        return
    end
    return msg
end

local LOG_LEVEL_OPTIONS = {
    [LOG_LEVEL.TRACE] = { "trace", 0x01 },
    [LOG_LEVEL.DEBUG] = { "debug", 0x01 },
    [LOG_LEVEL.INFO]  = { "info", 0x00 },
    [LOG_LEVEL.WARN]  = { "warn", 0x01 },
    [LOG_LEVEL.ERROR] = { "err", 0x01 },
    [LOG_LEVEL.FATAL] = { "fatal", 0x01 | 0x02 }
}
for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, flag = tunpack(conf)
    logger[lvl_name]     = function(fmt, ...)
        local msg = logger_output(flag, "", lvl, lvl_name, fmt, ...)
        if msg and not dispatching then
            dispatching = true
            for monitor, mlvl in pairs(monitors) do
                if lvl >= mlvl then
                    monitor:dispatch_log(msg, lvl_name)
                end
            end
            dispatching = false
        end
    end
end

for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, flag = tunpack(conf)
    logfeature[lvl_name] = function(feature, path, prefix, def)
        if not feature then
            local info = dgetinfo(2, "S")
            feature    = fsstem(info.short_src)
        end
        log.add_dest(feature, path)
        log.ignore_prefix(feature, prefix)
        log.ignore_def(feature, def)
        return function(fmt, ...)
            logger_output(flag, feature, lvl, lvl_name, fmt, ...)
        end
    end
end
