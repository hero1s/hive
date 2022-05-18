--basic.lua

--系统扩展函数名字空间
math_ext     = math_ext or {}
table_ext    = table_ext or {}
string_ext   = string_ext or {}
io_ext       = io_ext or {}
datetime_ext = datetime_ext or {}

--加载basic文件
import("basic/math.lua")
import("basic/table.lua")
import("basic/string.lua")
import("basic/logger.lua")
import("basic/io.lua")
import("basic/datetime.lua")

import("basic/oop/enum.lua")
import("basic/oop/class.lua")
import("basic/oop/mixin.lua")
import("basic/oop/property.lua")
import("constant.lua")

import("basic/console.lua")
import("basic/listener.lua")
import("basic/signal.lua")
import("basic/environ.lua")

local log_err    = logger.err
local sformat    = string.format
local dgetinfo   = debug.getinfo
local dtraceback = debug.traceback

--函数装饰器: 保护性的调用指定函数,如果出错则写日志
--主要用于一些C回调函数,它们本身不写错误日志
--通过这个装饰器,方便查错
function hive.xpcall(func, format, ...)
    local ok, err = xpcall(func, dtraceback, ...)
    if not ok then
        log_err(format, err)
    end
end

function hive.xpcall_quit(func, format, ...)
    local ok, err = xpcall(func, dtraceback, ...)
    if not ok then
        log_err(format, err)
        hive.run = nil
    end
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

function hive.enum(ename, ekey)
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
