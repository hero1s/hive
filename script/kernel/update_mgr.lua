--update_mgr.lua
local ltimer         = require("ltimer")
local lhelper        = require("lhelper")
local mem_usage      = lhelper.mem_usage
local lclock_ms      = ltimer.clock_ms
local pairs          = pairs
local odate          = os.date
local log_info       = logger.info
local log_warn       = logger.warn
local log_err        = logger.err
local sig_check      = signal.check
local tunpack        = table.unpack
local collectgarbage = collectgarbage
local cut_tail       = math_ext.cut_tail
local mregion        = math_ext.region
local is_same_day    = datetime_ext.is_same_day

local timer_mgr      = hive.get("timer_mgr")
local thread_mgr     = hive.get("thread_mgr")
local event_mgr      = hive.get("event_mgr")

local WTITLE         = hive.worker_title
local FAST_MS        = hive.enum("PeriodTime", "FAST_MS")
local HALF_MS        = hive.enum("PeriodTime", "HALF_MS")
local SECOND_5_MS    = hive.enum("PeriodTime", "SECOND_5_MS")

local UpdateMgr      = singleton()
local prop           = property(UpdateMgr)
prop:reader("last_day", 0)
prop:reader("last_hour", 0)
prop:reader("last_frame", 0)
prop:reader("last_minute", 0)
prop:reader("last_check_time", 0)
prop:reader("last_lua_mem_usage", 0)
prop:reader("max_lua_mem_usage", 0)
prop:reader("quit_objs", {})
prop:reader("hour_objs", {})
prop:reader("frame_objs", {})
prop:reader("fast_objs", {})
prop:reader("second_objs", {})
prop:reader("minute_objs", {})
prop:reader("next_events", {})
prop:reader("next_handlers", {})

local gc_step = 5

function UpdateMgr:__init()
    --注册订阅
    self:attach_frame(timer_mgr)
    self:attach_frame(thread_mgr)
    self:attach_second(thread_mgr)
    self:attach_minute(thread_mgr)
    --注册5秒定时器
    self.hotfix_able = environ.status("HIVE_HOTFIX")
    timer_mgr:loop(SECOND_5_MS, function()
        self:on_second_5s()
    end)
    --开启分代gc
    collectgarbage("generational")
end

function UpdateMgr:on_second_5s()
    --检查文件更新
    if self.hotfix_able then
        if hive.reload() > 0 then
            local config_mgr = hive.get("config_mgr")
            config_mgr:reload()
        end
    end
end

function UpdateMgr:collect_gc()
    local clock_ms  = lclock_ms()
    local mem       = cut_tail(mem_usage(), 1)
    local lua_mem_s = cut_tail(collectgarbage("count") / 1024, 1)
    collectgarbage("collect")
    local lua_mem_e = cut_tail(collectgarbage("count") / 1024, 1)
    log_warn("[UpdateMgr][collect_gc] %s m,lua:%s m --> %s m,cost time:%s", mem, lua_mem_s, lua_mem_e, lclock_ms() - clock_ms)
end

function UpdateMgr:update_next()
    for _, handler in pairs(self.next_handlers) do
        thread_mgr:fork(handler)
    end
    self.next_handlers = {}
    for _, events in pairs(self.next_events) do
        for event, args in pairs(events) do
            thread_mgr:fork(function()
                event_mgr:notify_trigger(event, tunpack(args))
            end)
        end
    end
    self.next_events = {}
end

function UpdateMgr:update_second(clock_ms)
    for obj in pairs(self.second_objs) do
        thread_mgr:fork(function()
            obj:on_second(clock_ms)
        end)
    end
    --增加增量gc步长
    collectgarbage("step", gc_step)
end

function UpdateMgr:update_fast(clock_ms)
    for obj in pairs(self.fast_objs) do
        thread_mgr:fork(function()
            obj:on_fast(clock_ms)
        end)
    end
    self.last_frame = clock_ms + FAST_MS
end

function UpdateMgr:update_minute(clock_ms)
    for obj in pairs(self.minute_objs) do
        thread_mgr:fork(function()
            obj:on_minute(clock_ms)
        end)
    end
    self:check_new_day()
    self:monitor_mem()
end

function UpdateMgr:update_hour(clock_ms, cur_hour, time)
    for obj in pairs(self.hour_objs) do
        thread_mgr:fork(function()
            obj:on_hour(clock_ms, cur_hour, time)
        end)
    end
    --每日4点执行一次全量更新
    if cur_hour == 4 then
        self:collect_gc()
    end
end

function UpdateMgr:update(now_ms, clock_ms)
    --业务更新
    thread_mgr:fork(function()
        local diff_ms = clock_ms - hive.clock_ms
        if diff_ms > HALF_MS and hive.frame > 1 then
            log_err("[UpdateMgr][update] last frame exec too long(%d ms)!,service:%s,mem:%s M", diff_ms, hive.name, self.last_lua_mem_usage)
        end
        --帧更新
        local frame   = hive.frame + 1
        hive.frame    = frame
        hive.now_ms   = now_ms
        hive.clock_ms = clock_ms
        for obj in pairs(self.frame_objs) do
            thread_mgr:fork(function()
                obj:on_frame(clock_ms, frame)
            end)
        end
        --更新帧逻辑
        self:update_next()
        --快帧更新
        if clock_ms < self.last_frame then
            return
        end
        self:update_fast(clock_ms)
        --检查信号
        if not WTITLE and self:check_signal() then
            return
        end
        --秒更新
        local now = now_ms // 1000
        if now == hive.now then
            return
        end
        hive.now = now
        self:update_second(clock_ms)
        --分更新
        local time = odate("*t", now)
        if time.min == self.last_minute then
            return
        end
        self.last_minute = time.min
        self:update_minute(clock_ms)
        --时更新
        local cur_hour = time.hour
        if cur_hour == self.last_hour then
            return
        end
        self.last_hour = cur_hour
        self:update_hour(clock_ms, cur_hour, time)
    end)
end

function UpdateMgr:check_signal()
    if sig_check() then
        if hive.run then
            hive.run = nil
            log_info("[UpdateMgr][check_signal]service quit for signal !")
            for obj in pairs(self.quit_objs) do
                thread_mgr:fork(function()
                    obj:on_quit()
                end)
            end
        end
        return true
    end
    return false
end

function UpdateMgr:check_new_day()
    if self.last_check_time > 0 and self.last_check_time < hive.now then
        if not is_same_day(self.last_check_time, hive.now) then
            log_info("[UpdateMgr][check_new_day] notify [%s] this time is new day!!!", hive.name)
            event_mgr:notify_trigger("evt_new_day")
        end
    end
    self.last_check_time = hive.now
end

--添加对象到小时更新循环
function UpdateMgr:attach_hour(obj)
    if not obj.on_hour then
        log_warn("[UpdateMgr][attach_hour] obj(%s) isn't on_hour method!", obj)
        return
    end
    self.hour_objs[obj] = true
end

function UpdateMgr:detach_hour(obj)
    self.hour_objs[obj] = nil
end

--添加对象到分更新循环
function UpdateMgr:attach_minute(obj)
    if not obj.on_minute then
        log_warn("[UpdateMgr][attach_minute] obj(%s) isn't on_minute method!", obj)
        return
    end
    self.minute_objs[obj] = true
end

function UpdateMgr:detach_minute(obj)
    self.minute_objs[obj] = nil
end

--添加对象到秒更新循环
function UpdateMgr:attach_second(obj)
    if not obj.on_second then
        log_warn("[UpdateMgr][attach_second] obj(%s) isn't on_second method!", obj)
        return
    end
    self.second_objs[obj] = true
end

function UpdateMgr:detach_second(obj)
    self.second_objs[obj] = nil
end

--添加对象到帧更新循环
function UpdateMgr:attach_frame(obj)
    if not obj.on_frame then
        log_warn("[UpdateMgr][attach_frame] obj(%s) isn't on_frame method!", obj)
        return
    end
    self.frame_objs[obj] = true
end

function UpdateMgr:detach_frame(obj)
    self.frame_objs[obj] = nil
end

--添加对象到快帧更新循环
function UpdateMgr:attach_fast(obj)
    if not obj.on_fast then
        log_warn("[UpdateMgr][attach_fast] obj(%s) isn't on_fast method!", obj)
        return
    end
    self.fast_objs[obj] = true
end

function UpdateMgr:detach_fast(obj)
    self.fast_objs[obj] = nil
end

--下一帧执行一个函数
function UpdateMgr:attach_next(key, func)
    self.next_handlers[key] = func
end

--下一帧执行一个事件
function UpdateMgr:attach_event(key, event, ...)
    local events = self.next_events[key]
    if not events then
        self.next_events[key] = { [event] = { ... } }
        return
    end
    events[event] = { ... }
end

--添加对象到程序退出通知列表
function UpdateMgr:attach_quit(obj)
    if not obj.on_quit then
        log_warn("[UpdateMgr][attach_quit] obj(%s) isn't on_quit method!", obj)
        return
    end
    self.quit_objs[obj] = true
end

function UpdateMgr:detach_quit(obj)
    self.quit_objs[obj] = nil
end

function UpdateMgr:monitor_mem()
    local lua_mem           = cut_tail(collectgarbage("count") / 1024, 1)
    local diff_mem          = lua_mem - self.last_lua_mem_usage
    self.last_lua_mem_usage = lua_mem
    if diff_mem > 1 then
        gc_step = gc_step + 1
    else
        if diff_mem < 0 then
            gc_step = gc_step - 1
        end
    end
    gc_step = mregion(gc_step, 1, 10)
    if lua_mem > self.max_lua_mem_usage then
        self.max_lua_mem_usage = lua_mem
    end
    if diff_mem > 1 and diff_mem / lua_mem > 0.01 then
        local cur_size, max_size = thread_mgr:size()
        log_warn("UpdateMgr][monitor_mem] lua_mem: +%s -> %s/%s M,threads:%s/%s,lock size:%s,gc_step:%s",
                 diff_mem, lua_mem, self.max_lua_mem_usage, cur_size, max_size, thread_mgr:lock_size(), gc_step)
    end
end

hive.update_mgr = UpdateMgr()

return UpdateMgr
