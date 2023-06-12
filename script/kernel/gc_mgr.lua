--手动垃圾回收模块
--适用于管理较大内存对象的模块
--两种情况下触发：1.内存距离上次清理增长超过传入阈值 2.持续未清理时间超过MAX_IDLE_TIME
--gc最终方案，根据内存增量，计算步长
-- 压测1W人在线，6秒增加内存186M，现网400人在线，6秒增加内存8M，暂定每秒增加20MB内存，就开启急速垃圾回收
local ltimer               = require("ltimer")
local lhelper              = require("lhelper")
local mem_usage            = lhelper.mem_usage
local lclock_ms            = ltimer.clock_ms
local collectgarbage       = collectgarbage
local mfloor               = math.floor
local log_info             = logger.info
local cut_tail             = math_ext.cut_tail

local gc_threshold         = 1024 * 1024 --MB
local gc_initflag          = false
local gc_stop_mem          = 0
local gc_running           = true
local gc_step_count        = 0
local gc_last_collect_time = 0

local MAX_IDLE_TIME        = 10 * 1000                  -- 空闲时间

local GC_MAX_STEP          = 1000                       -- gc最大回收速度
local GC_FAST_STEP         = 500                        -- gc快速垃圾回收，单步最大500ms
local GC_SLOW_STEP         = 100                        -- gc慢回收，单步最大100ms
local MEM_SIZE_FOR_FAST    = 100 * 1000                 -- gc快速回收内存大小,100MB
local MEM_SIZE_FOR_MAX     = 1000 * 1000                -- 超过1G内存，极限速度回收内存
local MEM_ALLOC_SPEED_MAX  = 20 * 1000                  -- 每秒消耗内存超过20M，开启急速gc
local PER_US_FOR_SECOND    = 1000                       -- 1秒=1000ms

local step_value           = GC_SLOW_STEP
local gc_use_time          = 0
local gc_start_time        = 0
local gc_free_time         = 0
local gc_start_mem         = 0
local gc_step_use_time_max = 0
local gc_step_time50_cnt   = 0                          -- 一个周期内，单步执行超过50ms的次数
local mem_cost_speed       = 0

local GcMgr                = singleton()
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
        gc_threshold = threshold
    end

    if not gc_initflag then
        gc_initflag = true
        collectgarbage("stop")
        gc_stop_mem = collectgarbage("count")
        gc_stop_mem = mfloor(gc_stop_mem)
        gc_running  = false
        log_info("gc stop autocollect, mem  curr count is %s", gc_stop_mem)
    end

    --collectgarbage("collect")
    local now_us = lclock_ms()
    if not gc_running then
        gc_start_mem   = collectgarbage("count")
        gc_start_mem   = mfloor(gc_start_mem)
        local mem_cost = gc_start_mem - gc_stop_mem
        if (mem_cost > gc_threshold) or gc_last_collect_time + MAX_IDLE_TIME < now_us then
            gc_running     = true
            gc_start_time  = now_us
            step_value     = GC_SLOW_STEP

            mem_cost_speed = 0
            if gc_last_collect_time > 0 then
                gc_free_time   = gc_start_time - gc_last_collect_time
                mem_cost_speed = (gc_free_time > PER_US_FOR_SECOND) and mem_cost / (gc_free_time / PER_US_FOR_SECOND) or MEM_ALLOC_SPEED_MAX
            end

            if gc_start_mem > MEM_SIZE_FOR_MAX or mem_cost_speed >= MEM_ALLOC_SPEED_MAX then
                step_value = GC_MAX_STEP
            elseif gc_start_mem > MEM_SIZE_FOR_FAST then
                step_value = GC_FAST_STEP
            end

            gc_step_time50_cnt = 0
            self:log_gc_start()
        end
    else
        local t1       = now_us
        gc_running     = not collectgarbage("step", step_value)
        local t2       = lclock_ms()
        local costTime = t2 - t1
        gc_use_time    = gc_use_time + costTime
        gc_step_count  = gc_step_count + 1
        if costTime > gc_step_use_time_max then
            gc_step_use_time_max = costTime
        end

        if costTime > 50 then
            gc_step_time50_cnt = gc_step_time50_cnt + 1
        end
        --log_info("gc step, step_count:%s cost_time: %s", gc_step_count, costTime)

        if not gc_running then
            gc_stop_mem          = collectgarbage("count")
            gc_stop_mem          = mfloor(gc_stop_mem)
            local old_step_value = step_value
            local gc_cycle       = lclock_ms() - gc_start_time
            local avg_time       = mfloor(gc_use_time / gc_step_count)
            self:log_gc_end(gc_cycle, avg_time, old_step_value)
            gc_step_count        = 0
            gc_use_time          = 0
            gc_step_use_time_max = 0
            gc_last_collect_time = lclock_ms()
        end
    end
end

function GcMgr:log_gc_start()
    if step_value >= GC_FAST_STEP then
        log_info("[log_gc_start] count is:%s,last mem is:%s,step value is:%s", gc_start_mem, gc_stop_mem, step_value)
    end
end

function GcMgr:log_gc_end(gc_cycle, avg_time, old_step_value)
    if step_value >= GC_FAST_STEP then
        log_info("[log_gc_end] step_count:%s,curr_mem:%s,last_mem:%s,cost_time:%s,cycle:%s,step_time_max:%s,step_time_avg:%s,free_time:%s,step_value:%s,step_time50_cnt:%s,mem_cost_speed:%s",
                 gc_step_count, gc_stop_mem, gc_start_mem, gc_use_time, gc_cycle, gc_step_use_time_max, avg_time, gc_free_time, old_step_value, gc_step_time50_cnt, mem_cost_speed)
    end
end

hive.gc_mgr = GcMgr()

return GcMgr
