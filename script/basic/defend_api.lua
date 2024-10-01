local lclock_ms  = timer.clock_ms
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
    if not ok and format then
        log_err(format, err)
    end
end

function hive.xpcall_ret(func, format, ...)
    local result = tpack(xpcall(func, dtraceback, ...))
    if not result[1] and format then
        log_err(format, result[2])
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

function hive.where_call(thread)
    local info = dgetinfo(thread or 3, "nSl") or {}
    return sformat("[%s:%d(%s)]", info.short_src or "C", info.currentline or 0, info.name or "")
end

-- 启动死循环监控
function hive.check_endless_loop(start)
    if not start then
        log_warn("close check_endless_loop !")
        dsethook()
        return
    end
    log_warn("open check_endless_loop will degrade performance!")
    local debug_hook = function()
        local now = lclock_ms()
        if now - hive.clock_ms >= 10000 then
            log_err("check_endless_loop:{}", dtraceback())
        end
    end
    dsethook(debug_hook, "l")
end

local xpcall_ret = hive.xpcall_ret

function hive.json_decode(json_str, result, numkeyable)
    local ok, res = xpcall_ret(json.decode, "[hive.json_decode] error:%s", json_str, numkeyable)
    if not ok then
        log_err("[hive][json_decode] err json_str:[{}],from:[{}]", json_str, hive.where_call())
    end
    if result then
        return ok, ok and res or nil
    else
        return ok and res or nil
    end
end

function hive.try_json_decode(json_str, result, numkeyable)
    local ok, res = xpcall_ret(json.decode, nil, json_str, numkeyable)
    if not ok then
        log_warn("[hive][try_json_decode] err json_str:[{}],from:[{}]", json_str, hive.where_call())
    end
    if result then
        return ok, ok and res or nil
    else
        return ok and res or nil
    end
end

function hive.json_encode(body, empty_as_arr, swline)
    local call_func = swline and json.pretty or json.encode
    local ok, jstr  = xpcall_ret(call_func, "[hive.json_encode] error:%s", body, empty_as_arr)
    if not ok then
        log_err("[hive][json_encode] err body:[{}],from:[{}]", body, hive.where_call())
    end
    return ok and jstr or ""
end