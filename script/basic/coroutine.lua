-- coroutine.lua
local tpack      = table.pack
local tunpack    = table.unpack
local raw_yield  = coroutine.yield
local raw_resume = coroutine.resume
local co_running = coroutine.running

local co_hookor  = hive.load("co_hookor")

--协程改造
function hive.init_coroutine()
    coroutine.yield  = function(...)
        local rco  = co_running()
        hive.trace = rco.trace
        if co_hookor then
            co_hookor:yield(rco)
        end
        return raw_yield(...)
    end
    coroutine.resume = function(co, ...)
        local rco = co_running()
        if co_hookor then
            co_hookor:yield(rco)
            co_hookor:resume(co)
        end
        hive.trace = rco.trace
        local args = tpack(raw_resume(co, ...))
        co.trace   = hive.trace
        if co_hookor then
            co_hookor:resume(co_running())
        end
        return tunpack(args)
    end
    hive.eval        = function(name)
        if co_hookor then
            return co_hookor:eval(name)
        end
    end
end

function hive.hook_coroutine(hooker)
    co_hookor      = hooker
    hive.co_hookor = hooker
end
