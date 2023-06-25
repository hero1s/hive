--手动垃圾回收模块
--适用于管理较大内存对象的模块
--两种情况下触发：1.内存距离上次清理增长超过传入阈值 2.持续未清理时间超过MAX_IDLE_TIME
--gc最终方案，根据内存增量，计算步长
-- 压测1W人在线，6秒增加内存186M，现网400人在线，6秒增加内存8M，暂定每秒增加20MB内存，就开启急速垃圾回收
local ltimer              = require("ltimer")
local lhelper             = require("lhelper")
local mem_usage           = lhelper.mem_usage
local lclock_ms           = ltimer.clock_ms
local collectgarbage      = collectgarbage
local mfloor              = math.floor
local log_info            = logger.info
local cut_tail            = math_ext.cut_tail

local MAX_IDLE_TIME       = 10 * 1000                  -- 空闲时间
local GC_MAX_STEP         = 1000                       -- gc最大回收速度
local GC_FAST_STEP        = 500                        -- gc快速垃圾回收，单步最大500ms
local GC_SLOW_STEP        = 100                        -- gc慢回收，单步最大100ms
local MEM_SIZE_FOR_FAST   = 100 * 1000                 -- gc快速回收内存大小,100MB
local MEM_SIZE_FOR_MAX    = 1000 * 1000                -- 超过1G内存，极限速度回收内存
local MEM_ALLOC_SPEED_MAX = 20 * 1000                  -- 每秒消耗内存超过20M，开启急速gc
local PER_US_FOR_SECOND   = 1000                       -- 1秒=1000ms

local GcMgr               = singleton()
local prop                = property(GcMgr)
prop:reader("gc_threshold", 1024 * 1024)
prop:reader("gc_initflag", false)
prop:reader("gc_stop_mem", 0)
prop:reader("gc_running", true)
prop:reader("gc_step_count", 0)
prop:reader("gc_last_collect_time", 0)
prop:reader("step_value", GC_SLOW_STEP)
prop:reader("gc_use_time", 0)
prop:reader("gc_start_time", 0)
prop:reader("gc_free_time", 0)
prop:reader("gc_start_mem", 0)
prop:reader("gc_step_use_time_max", 0)
prop:reader("gc_step_time50_cnt", 0)-- 一个周期内，单步执行超过50ms的次数
prop:reader("mem_cost_speed", 0)

function GcMgr:__init()
end

function GcMgr:on_fast(clock_ms)
    self:update()
end

function GcMgr:collect_gc()
    local clock_ms  = lclock_ms()
    local mem       = cut_tail(mem_usage(), 1)
    local lua_mem_s = cut_tail(collectgarbage("count") / 1024, 1)
    collectgarbage("collect")
    local lua_mem_e = cut_tail(collectgarbage("count") / 1024, 1)
    log_info("[GcMgr][collect_gc] %s m,lua:%s m --> %s m,cost time:%s", mem, lua_mem_s, lua_mem_e, lclock_ms() - clock_ms)
end

function GcMgr:update(threshold)
    if threshold ~= nil and threshold > 1024 * 32 then
        self.gc_threshold = threshold
    end

    if not self.gc_initflag then
        self.gc_initflag = true
        collectgarbage("stop")
        self.gc_stop_mem = mfloor(collectgarbage("count"))
        self.gc_running  = false
        log_info("gc stop autocollect, mem  curr count is %s", self.gc_stop_mem)
    end

    --collectgarbage("collect")
    local now_us = lclock_ms()
    if not self.gc_running then
        self.gc_start_mem = mfloor(collectgarbage("count"))
        local mem_cost    = self.gc_start_mem - self.gc_stop_mem
        if (mem_cost > self.gc_threshold) or self.gc_last_collect_time + MAX_IDLE_TIME < now_us then
            self.gc_running     = true
            self.gc_start_time  = now_us
            self.step_value     = GC_SLOW_STEP

            self.mem_cost_speed = 0
            if self.gc_last_collect_time > 0 then
                self.gc_free_time   = self.gc_start_time - self.gc_last_collect_time
                self.mem_cost_speed = (self.gc_free_time > PER_US_FOR_SECOND) and mem_cost / (self.gc_free_time / PER_US_FOR_SECOND) or MEM_ALLOC_SPEED_MAX
            end

            if self.gc_start_mem > MEM_SIZE_FOR_MAX or self.mem_cost_speed >= MEM_ALLOC_SPEED_MAX then
                self.step_value = GC_MAX_STEP
            elseif self.gc_start_mem > MEM_SIZE_FOR_FAST then
                self.step_value = GC_FAST_STEP
            end

            self.gc_step_time50_cnt = 0
            self:log_gc_start()
        end
    else
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
        --log_info("gc step, step_count:%s cost_time: %s", gc_step_count, costTime)

        if not self.gc_running then
            self.gc_stop_mem     = mfloor(collectgarbage("count"))
            local old_step_value = self.step_value
            local gc_cycle       = lclock_ms() - self.gc_start_time
            local avg_time       = mfloor(self.gc_use_time / self.gc_step_count)
            self:log_gc_end(gc_cycle, avg_time, old_step_value)
            self.gc_step_count        = 0
            self.gc_use_time          = 0
            self.gc_step_use_time_max = 0
            self.gc_last_collect_time = lclock_ms()
        end
    end
end

function GcMgr:log_gc_start()
    if self.step_value > GC_SLOW_STEP then
        log_info("[log_gc_start] count is:%s,last mem is:%s,step value is:%s", self.gc_start_mem, self.gc_stop_mem, self.step_value)
    end
end

function GcMgr:log_gc_end(gc_cycle, avg_time, old_step_value)
    if self.step_value > GC_SLOW_STEP then
        log_info("[log_gc_end] step_count:%s,curr_mem:%s,last_mem:%s,cost_time:%s,cycle:%s,step_time_max:%s,step_time_avg:%s,free_time:%s,step_value:%s,step_time50_cnt:%s,mem_cost_speed:%s",
                 self.gc_step_count, self.gc_stop_mem, self.gc_start_mem, self.gc_use_time, gc_cycle, self.gc_step_use_time_max, avg_time, self.gc_free_time, old_step_value, self.gc_step_time50_cnt, self.mem_cost_speed)
    end
end

hive.gc_mgr = GcMgr()

return GcMgr
