--手动垃圾回收模块
--适用于管理较大内存对象的模块
--两种情况下触发：1.内存距离上次清理增长超过阈值 2.持续未清理时间超过MAX_IDLE_TIME
--gc最终方案，根据回收耗时及上一轮的回收步数，计算步长
local lhelper                    = require("lhelper")
local mem_usage                  = lhelper.mem_usage
local lclock_ms                  = timer.clock_ms
local collectgarbage             = collectgarbage
local mfloor                     = math.floor
local log_warn                   = logger.warn
local cut_tail                   = math_ext.cut_tail
local mregion                    = math_ext.region

local MAX_IDLE_TIME<const>       = 5 * 1000                   -- 空闲时间
local GC_FAST_STEP               = 200                        -- gc快速回收
local GC_SLOW_STEP               = 50                         -- gc慢回收
local MEM_ALLOC_SPEED_MAX<const> = 10 * 1024                  -- 每秒消耗内存超过10M，开启急速gc
local PER_US_FOR_SECOND<const>   = 1000                       -- 1秒=1000ms

local GcMgr                      = singleton()
local prop                       = property(GcMgr)
prop:reader("gc_threshold", 20 * 1024)
prop:reader("gc_stop_mem", 0)
prop:reader("gc_running", true)
prop:reader("gc_step_count", 0)
prop:reader("gc_last_collect_time", 0)
prop:reader("step_value", GC_SLOW_STEP)
prop:reader("step_inc", 0)
prop:reader("gc_use_time", 0)
prop:reader("gc_start_time", 0)
prop:reader("gc_free_time", 0)
prop:reader("gc_start_mem", 0)
prop:reader("gc_step_use_time_max", 0)
prop:reader("gc_step_time50_cnt", 0)-- 一个周期内，单步执行超过50ms的次数
prop:reader("mem_cost_speed", 0)
prop:reader("open_gc_step", 1)
prop:reader("is_step_gc", false)
prop:reader("cycle_need", 2)

function GcMgr:__init()
    local open_gc   = environ.number("HIVE_GC_OPEN", 1)
    local slow_step = environ.number("HIVE_GC_SLOW_STEP", GC_SLOW_STEP)
    local fast_step = environ.number("HIVE_GC_FAST_STEP", GC_FAST_STEP)
    local pause     = environ.number("HIVE_GC_PAUSE", 120)
    local stepmul   = environ.number("HIVE_GC_STEPMUL", 500)
    self:set_gc_step(open_gc, slow_step, fast_step)
    self:set_gc_speed(pause, stepmul)
end

function GcMgr:set_gc_speed(pause, step_mul)
    pause    = mregion(mfloor(pause), 110, 200)
    step_mul = mregion(mfloor(step_mul), 200, 1000)
    collectgarbage("setpause", pause)
    collectgarbage("setstepmul", step_mul)
    log_warn("[GcMgr][set_gc_speed] pause:%s,step_mul:%s", pause, step_mul)
end

function GcMgr:set_gc_step(open, slow_step, fast_step)
    self.open_gc_step = open
    self:switch_gc(open > 0)
    self.gc_stop_mem = mfloor(collectgarbage("count"))
    self.gc_running  = false
    GC_SLOW_STEP     = mfloor(mregion(slow_step or GC_SLOW_STEP, 50, 100)) -- gc慢回收
    GC_FAST_STEP     = mfloor(mregion(fast_step or GC_FAST_STEP, 100, 300)) -- gc快速回收
    log_warn("[GcMgr][set_gc_step] open:%s,slow_step:%s,fast_step:%s", open, slow_step, fast_step)
end

function GcMgr:lua_mem_size()
    return cut_tail(collectgarbage("count") / 1024, 1)
end

function GcMgr:mem_size()
    return cut_tail(mem_usage(), 1)
end

function GcMgr:real_mem_size()
    return cut_tail(mem_usage(true), 1)
end

function GcMgr:full_gc()
    local clock_ms  = lclock_ms()
    local mem       = self:mem_size()
    local real_mem  = self:real_mem_size()
    local lua_mem_s = self:lua_mem_size()
    collectgarbage("collect")
    local lua_mem_e = self:lua_mem_size()
    log_warn("[GcMgr][full_gc] {} m,{} m,lua:{} m --> {} m,cost time:{}", mem, real_mem, lua_mem_s, lua_mem_e, lclock_ms() - clock_ms)
    return lua_mem_e
end

function GcMgr:run_step(now_us)
    self.gc_running    = not collectgarbage("step", self.step_value)
    local costTime     = lclock_ms() - now_us
    self.gc_use_time   = self.gc_use_time + costTime
    self.gc_step_count = self.gc_step_count + 1
    if costTime > self.gc_step_use_time_max then
        self.gc_step_use_time_max = costTime
    end
    if costTime > 50 then
        self.gc_step_time50_cnt = self.gc_step_time50_cnt + 1
    end
    if not self.gc_running then
        self:log_gc_end()
    end
    self:calc_step_value(costTime)
    return costTime
end

function GcMgr:update()
    if not self.is_step_gc then
        return -1
    end
    local now_us = lclock_ms()
    if self.gc_running then
        return self:run_step(now_us)
    end
    self.gc_start_mem = mfloor(collectgarbage("count"))
    local mem_cost    = self.gc_start_mem - self.gc_stop_mem
    if (mem_cost > self.gc_threshold) or self.gc_last_collect_time + MAX_IDLE_TIME < now_us then
        self:log_gc_start(now_us, mem_cost)
    end
    return 0
end

function GcMgr:calc_step_value(cost_time)
    if cost_time > 50 and self.step_inc > 0 then
        self.step_value = mregion(mfloor(self.step_value * 0.7), GC_SLOW_STEP, GC_FAST_STEP)
        self.step_inc   = self.step_inc - 1
    elseif cost_time < 5 and self.step_inc < 3 then
        self.step_value = mregion(mfloor(self.step_value * 1.5), GC_SLOW_STEP, GC_FAST_STEP)
        self.step_inc   = self.step_inc + 1
    end
end

function GcMgr:log_gc_start(now_us, mem_cost)
    self.gc_running     = true
    self.gc_start_time  = now_us
    self.mem_cost_speed = 0
    self.step_value     = GC_SLOW_STEP
    self.step_inc       = 0

    if self.gc_last_collect_time > 0 then
        self.gc_free_time   = self.gc_start_time - self.gc_last_collect_time
        self.mem_cost_speed = (self.gc_free_time > PER_US_FOR_SECOND) and mem_cost / (self.gc_free_time / PER_US_FOR_SECOND) or MEM_ALLOC_SPEED_MAX
        self.step_value     = mregion(mfloor(self.mem_cost_speed / 10), GC_SLOW_STEP, GC_FAST_STEP / 2)
    end

    self.gc_step_time50_cnt   = 0
    self.gc_step_count        = 0
    self.gc_use_time          = 0
    self.gc_step_use_time_max = 0
end

function GcMgr:log_gc_end()
    self.gc_stop_mem = mfloor(collectgarbage("count"))
    local cycle_time = lclock_ms() - self.gc_start_time
    local avg_time   = mfloor(self.gc_use_time / self.gc_step_count)
    if self.gc_step_time50_cnt > 1 then
        local gc_info = {
            step_count      = self.gc_step_count,
            curr_mem        = self.gc_stop_mem,
            last_mem        = self.gc_start_mem,
            recycle_mem     = self.gc_start_mem - self.gc_stop_mem,
            cost_time       = self.gc_use_time,
            cycle_time      = cycle_time,
            step_time_max   = self.gc_step_use_time_max,
            step_time_avg   = avg_time,
            free_time       = self.gc_free_time,
            step_value      = self.step_value,
            step_time50_cnt = self.gc_step_time50_cnt,
            mem_cost_speed  = self.mem_cost_speed,
        }
        log_warn("[GcMgr][log_gc_end] {}", gc_info)
    end
    self.gc_last_collect_time = lclock_ms()
    self.cycle_need           = self.cycle_need - 1
    if self.open_gc_step == 1 and self.cycle_need < 0 or self.gc_step_time50_cnt > 2 then
        self:switch_gc(false)
    end
end

function GcMgr:dump_mem_obj(less_count)
    local thread_mgr = hive.get("thread_mgr")
    local obj_counts = class_review(less_count)
    local info       = {
        objs    = obj_counts,
        lua_mem = self:lua_mem_size(),
        thread  = {
            co_lock = thread_mgr:lock_size(),
            co_wait = thread_mgr:wait_size(),
            co_idle = thread_mgr:idle_size(),
        }
    }
    logger.dump("[GcMgr][dump_mem_obj]:{}", info)
    return info
end

--切换gc
function GcMgr:switch_gc(step_gc)
    self.is_step_gc = step_gc
    if step_gc then
        collectgarbage("stop")
        self.cycle_need = 2
    else
        collectgarbage("restart")
    end
end

--检测进入快速gc
function GcMgr:check_enter_step_gc()
    if self.open_gc_step == 0 or self.is_step_gc then
        return
    end
    self:switch_gc(true)
end

hive.gc_mgr = GcMgr()

return GcMgr
