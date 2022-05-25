--perfeval_mgr.lua
local ltimer = require("ltimer")

local pairs         = pairs
local tpack         = table.pack
local tunpack       = table.unpack
local env_status    = environ.status
local raw_yield     = hive.yield
local raw_resume    = hive.resume
local raw_running   = hive.running
local lclock_ms     = ltimer.clock_ms

local EvalSlot      = import("kernel/object/eval_slot.lua")
local event_mgr     = hive.get("event_mgr")

local PerfevalMgr = singleton()
local prop = property(PerfevalMgr)
prop:reader("eval_id", 0)
prop:reader("perfeval", false)  --性能开关
prop:reader("eval_list", {})    --协程评估表
function PerfevalMgr:__init()
    self.perfeval = env_status("HIVE_PERFEVAL")
end

function PerfevalMgr:yield()
    if self.perfeval then
        local clock_ms = lclock_ms()
        local yield_co = raw_running()
        local eval_cos = self.eval_list[yield_co]
        for _, eval_data in pairs(eval_cos or {}) do
            eval_data.yield_tick = clock_ms
        end
    end
end

function PerfevalMgr:resume(co)
    if self.perfeval then
        local clock_ms = lclock_ms()
        local resume_co = co or raw_running()
        local eval_cos = self.eval_list[resume_co]
        for _, eval_data in pairs(eval_cos or {}) do
            if eval_data.yield_tick > 0 then
                local pause_time = clock_ms - eval_data.yield_tick
                eval_data.yield_time = eval_data.yield_time + pause_time
                eval_data.yield_tick = 0
            end
        end
    end
end

function PerfevalMgr:get_eval_id()
    self.eval_id = self.eval_id + 1
    if self.eval_id >= 0x7fffffff then
        self.eval_id = 1
    end
    return self.eval_id
end

function PerfevalMgr:eval(eval_name)
    if self.perfeval then
        return EvalSlot(self, eval_name)
    end
end

function PerfevalMgr:start(eval_name)
    local co = raw_running()
    local eval_id = self:get_eval_id()
    local eval_data = {
        co = co,
        yield_time = 0,
        eval_id = eval_id,
        eval_name = eval_name,
        begin_time = lclock_ms(),
    }
    local eval_cos = self.eval_list[co]
    if eval_cos then
        eval_cos[eval_id] = eval_data
    else
        self.eval_list[co] = { [eval_id] = eval_data }
    end
    return eval_data
end

function PerfevalMgr:stop(eval_data)
    local clock_ms = lclock_ms()
    event_mgr:notify_listener("on_perfeval", eval_data, clock_ms)
    self.eval_list[eval_data.co][eval_data.eval_id] = nil
end

local perfeval_mgr = PerfevalMgr()

--协程改造
coroutine.yield = function(...)
    perfeval_mgr:yield()
    return raw_yield(...)
end

coroutine.resume = function(co, ...)
    perfeval_mgr:yield()
    perfeval_mgr:resume(co)
    local args = tpack(raw_resume(co, ...))
    perfeval_mgr:resume()
    return tunpack(args)
end

hive.perfeval_mgr = perfeval_mgr

return PerfevalMgr
