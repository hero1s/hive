--logger.lua
--logger功能支持
local llog          = require("lualog")
local lbuffer       = require("lbuffer")
local lstdfs        = require("lstdfs")

local pcall         = pcall
local pairs         = pairs
local sformat       = string.format
local dgetinfo      = debug.getinfo
local tpack         = table.pack
local tunpack       = table.unpack
local fsstem        = lstdfs.stem
local lserialize    = lbuffer.serialize

local LOG_LEVEL     = llog.LOG_LEVEL
local driver        = hive.get_logger()

logger = {}
logfeature = {}

function logger.init()
    --配置日志信息
    local service_name, index = hive.service_name, hive.index
    local path = environ.get("HIVE_LOG_PATH", "./logs/")
    local rolltype = environ.number("HIVE_LOG_ROLL", 0)
    local maxline = environ.number("HIVE_LOG_LINE", 100000)
    driver.option(path, service_name, index, rolltype, maxline);
    --设置日志过滤
    logger.filter(environ.number("HIVE_LOG_LVL",1))
    --添加输出目标
    driver.add_dest(service_name);
    driver.add_lvl_dest(LOG_LEVEL.ERROR)
    --设置daemon
    driver.daemon(environ.status("HIVE_DAEMON"))
    --graylog
    local logaddr = environ.get("HIVE_GRAYLOG_ADDR")
    if logaddr then
        --local GrayLog = import("driver/graylog.lua")
        --logger.graydriver = GrayLog(logaddr)
    end
end

function logger.daemon(daemon)
    driver.daemon(daemon)
end

function logger.feature(name)
    if not logfeature.features then
        logfeature.features = {}
    end
    if not logfeature.features[name] then
        logfeature.features[name] = true
        driver.add_dest(name)
    end
end

function logger.set_webhook(webhook)
    logger.webhook = webhook
end

function logger.set_monitor(monitor)
    logger.monitor = monitor
end

function logger.filter(level)
    for lvl = LOG_LEVEL.DEBUG, LOG_LEVEL.FATAL do
        --driver.filter(level, on/off)
        driver.filter(lvl, lvl >= level)
    end
end

local function logger_output(feature, lvl, lvl_name, fmt, log_conf, ...)
    if driver.is_filter(lvl) then
        return false
    end
    local content
    local lvl_func, extend, notify, swline, graylog = tunpack(log_conf)
    if extend then
        local args = tpack(...)
        for i, arg in pairs(args) do
            if type(arg) == "table" then
                args[i] = lserialize(arg, swline and 1 or 0)
            end
        end
        content = sformat(fmt, tunpack(args, 1, args.n))
    else
        content = sformat(fmt, ...)
    end
    local webhook = logger.webhook
    if notify and webhook then
        webhook:notify(lvl_name, content)
    end
    local monitor = logger.monitor
    if monitor then
        monitor:notify(lvl_name, content)
    end
    local graydriver = logger.graydriver
    if graylog and graydriver then
        graydriver:write(content, lvl)
    end
    return lvl_func(content, feature)
end

local LOG_LEVEL_OPTIONS = {
                                     --lvl_func,     extend, notify, swline, graylog
    [LOG_LEVEL.INFO]    = { "info",  { driver.info,  false,  false,  false,  true } },
    [LOG_LEVEL.WARN]    = { "warn",  { driver.warn,  true,   false,  true,   true } },
    [LOG_LEVEL.DUMP]    = { "dump",  { driver.dump,  true,   false,  true,   true } },
    [LOG_LEVEL.DEBUG]   = { "debug", { driver.debug, true,   false,  false,  false} },
    [LOG_LEVEL.ERROR]   = { "err",   { driver.error, true,   true,   true,   true } },
    [LOG_LEVEL.FATAL]   = { "fatal", { driver.fatal, true,   true,   true,   true } }
}
for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logger[lvl_name] = function(fmt, ...)
        local ok, res = pcall(logger_output, "", lvl, lvl_name, fmt, log_conf, ...)
        if not ok then
            local info = dgetinfo(2, "S")
            driver.warn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
            return false
        end
        return res
    end
end

for lvl, conf in pairs(LOG_LEVEL_OPTIONS) do
    local lvl_name, log_conf = tunpack(conf)
    logfeature[lvl_name] = function(feature)
        if not feature then
            local info = dgetinfo(2, "S")
            feature = fsstem(info.short_src)
        end
        logger.feature(feature)
        return function(fmt, ...)
            local ok, res = pcall(logger_output, feature, lvl, lvl_name, fmt, log_conf, ...)
            if not ok then
                local info = dgetinfo(2, "S")
                driver.warn(sformat("[logger][%s] format failed: %s, source(%s:%s)", lvl_name, res, info.short_src, info.linedefined))
                return false
            end
            return res
        end
    end
end
