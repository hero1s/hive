--perfeval_mgr.lua
local ltimer      = require("ltimer")
local lclock_ms   = ltimer.clock_ms

local tinsert     = table.insert
local tsort       = table.sort
local pairs       = pairs
local co_running  = coroutine.running
local env_status  = environ.status
local log_warn    = logger.warn

local EvalSlot    = import("kernel/object/eval_slot.lua")
local event_mgr   = hive.get("event_mgr")
local update_mgr  = hive.get("update_mgr")

local PerfevalMgr = singleton()
local prop        = property(PerfevalMgr)
prop:reader("eval_id", 0)
prop:reader("perfeval", false)  --性能开关
prop:reader("eval_list", {})    --协程评估表
prop:reader("perfevals", {})    --性能统计

function PerfevalMgr:__init()
    self.perfeval = env_status("HIVE_PERFEVAL")
    if self.perfeval then
        hive.hook_coroutine(self)
    end
    update_mgr:attach_quit(self)

end

function PerfevalMgr:yield()
    local clock_ms = lclock_ms()
    local yield_co = co_running()
    local eval_cos = self.eval_list[yield_co]
    for _, eval_data in pairs(eval_cos or {}) do
        eval_data.yield_tick = clock_ms
    end
end

function PerfevalMgr:resume(co)
    local clock_ms  = lclock_ms()
    local resume_co = co or co_running()
    local eval_cos  = self.eval_list[resume_co]
    for _, eval_data in pairs(eval_cos or {}) do
        if eval_data.yield_tick > 0 then
            local pause_time     = clock_ms - eval_data.yield_tick
            eval_data.yield_time = eval_data.yield_time + pause_time
            eval_data.yield_tick = 0
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
    local co        = co_running()
    local eval_id   = self:get_eval_id()
    local eval_data = {
        co         = co,
        yield_time = 0,
        eval_id    = eval_id,
        eval_name  = eval_name,
        begin_time = lclock_ms(),
    }
    local eval_cos  = self.eval_list[co]
    if eval_cos then
        eval_cos[eval_id] = eval_data
    else
        self.eval_list[co] = { [eval_id] = eval_data }
    end
    return eval_data
end

function PerfevalMgr:stop(eval_data)
    local clock_ms   = lclock_ms()
    local total_time = clock_ms - eval_data.begin_time
    local fields     = {
        total_time = total_time,
        yield_time = eval_data.yield_time,
        eval_time  = total_time - eval_data.yield_time
    }
    event_mgr:notify_listener("on_perfeval", eval_data.eval_name, fields)
    if total_time > 1 then
        self:write_perf(eval_data.eval_name, fields)
    end
    self.eval_list[eval_data.co][eval_data.eval_id] = nil
end

function PerfevalMgr:write_perf(eval_name, fields)
    local eval = self.perfevals[eval_name]
    if eval then
        eval.total_time    = eval.total_time + fields.total_time
        eval.yield_time    = eval.yield_time + fields.yield_time
        eval.eval_time     = eval.eval_time + fields.eval_time
        eval.max_eval_time = (fields.eval_time > eval.max_eval_time) and fields.eval_time or eval.max_eval_time
        eval.count         = eval.count + 1
    else
        self.perfevals[eval_name] = {
            total_time    = fields.total_time or 0,
            yield_time    = fields.yield_time or 0,
            eval_time     = fields.eval_time or 0,
            max_eval_time = fields.eval_time or 0,
            count         = 1
        }
    end
end

function PerfevalMgr:dump_perf()
    local sort_infos = {}
    for i, v in pairs(self.perfevals) do
        local info = {
            name          = i,
            total_time    = v.total_time / v.count,
            yield_time    = v.yield_time / v.count,
            eval_time     = v.eval_time / v.count,
            max_eval_time = v.max_eval_time,
            count         = v.count
        }
        tinsert(sort_infos, info)
    end
    tsort(sort_infos, function(a, b)
        return a.total_time > b.total_time
    end)
    if next(sort_infos) then
        log_warn("[StatisMgr][dump_perf] \n %s", sort_infos)
    end
end

function PerfevalMgr:on_quit()
    self:dump_perf()
end

hive.perfeval_mgr = PerfevalMgr()

return PerfevalMgr
