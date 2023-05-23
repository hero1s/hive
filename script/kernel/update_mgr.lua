--update_mgr.lua
local lcodec         = require("lcodec")
local ltimer         = require("ltimer")
local lhelper        = require("lhelper")
local mem_usage      = lhelper.mem_usage
local lclock_ms      = ltimer.clock_ms
local ltime          = ltimer.time
local pairs          = pairs
local odate          = os.date
local log_info       = logger.info
local log_warn       = logger.warn
local log_err        = logger.err
local sig_get        = signal.get
local sig_check      = signal.check
local signal_quit    = signal.quit
local sig_reload     = signal.reload
local tweak          = table_ext.weak
local collectgarbage = collectgarbage
local guid_new       = lcodec.guid_new
local cut_tail       = math_ext.cut_tail
local is_same_day    = datetime_ext.is_same_day

local timer_mgr      = hive.get("timer_mgr")
local thread_mgr     = hive.get("thread_mgr")
local event_mgr      = hive.get("event_mgr")

local WTITLE         = hive.worker_title
local FAST_MS        = hive.enum("PeriodTime", "FAST_MS")
local HALF_MS        = hive.enum("PeriodTime", "HALF_MS")
local ServiceStatus  = enum("ServiceStatus")

local UpdateMgr      = singleton()
local prop           = property(UpdateMgr)
prop:reader("last_day", 0)
prop:reader("last_hour", 0)
prop:reader("last_frame", 0)
prop:reader("last_minute", 0)
prop:reader("last_check_time", 0)
prop:reader("quit_objs", {})
prop:reader("hour_objs", {})
prop:reader("frame_objs", {})
prop:reader("fast_objs", {})
prop:reader("minute_objs", {})
prop:reader("second_objs", {})
prop:reader("second5_objs", {})
prop:reader("second30_objs", {})

local gc_step = 10

function UpdateMgr:__init()
    --设置弱表
    tweak(self.quit_objs)
    tweak(self.hour_objs)
    tweak(self.fast_objs)
    tweak(self.frame_objs)
    tweak(self.second_objs)
    tweak(self.second5_objs)
    tweak(self.second30_objs)
    tweak(self.minute_objs)
    --注册订阅
    self:attach_frame(timer_mgr)
    self:attach_frame(event_mgr)
    self:attach_fast(thread_mgr)
    self:attach_second(event_mgr)
    self:attach_second(thread_mgr)
    self:attach_minute(thread_mgr)

    self.hotfix_able = environ.status("HIVE_HOTFIX")
    self:setup()
end

function UpdateMgr:setup()
    hive.now_ms, hive.clock_ms = ltime()
    hive.now                   = hive.now_ms // 1000
    local time                 = odate("*t", hive.now)
    self.last_minute           = time.min
    self.last_hour             = time.hour
end

function UpdateMgr:collect_gc()
    local clock_ms  = lclock_ms()
    local mem       = cut_tail(mem_usage(), 1)
    local lua_mem_s = cut_tail(collectgarbage("count") / 1024, 1)
    collectgarbage("collect")
    local lua_mem_e = cut_tail(collectgarbage("count") / 1024, 1)
    log_warn("[UpdateMgr][collect_gc] %s m,lua:%s m --> %s m,cost time:%s", mem, lua_mem_s, lua_mem_e, lclock_ms() - clock_ms)
end

function UpdateMgr:update_second(clock_ms)
    for obj, key in pairs(self.second_objs) do
        thread_mgr:entry(key, function()
            obj:on_second(clock_ms)
        end)
    end
end

function UpdateMgr:update_fast(clock_ms)
    for obj, key in pairs(self.fast_objs) do
        thread_mgr:entry(key, function()
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

function UpdateMgr:update(scheduler, now_ms, clock_ms)
    --业务更新
    thread_mgr:fork(function()
        local diff_ms = clock_ms - hive.clock_ms
        if diff_ms > HALF_MS and hive.frame > 1 then
            local cur_size, idle_size = thread_mgr:size()
            log_err("[UpdateMgr][update] last frame exec too long(%d ms)!,service:%s,threads:%s/%s,lock size:%s,gc_step:%s",
                    diff_ms, hive.name, cur_size, idle_size, thread_mgr:lock_size(), gc_step)
        end
        --帧更新
        local frame   = hive.frame + 1
        hive.frame    = frame
        hive.now_ms   = now_ms
        hive.clock_ms = clock_ms
        for obj, key in pairs(self.frame_objs) do
            thread_mgr:entry(key, function()
                obj:on_frame(clock_ms, frame)
            end)
        end
        --快帧更新
        if clock_ms < self.last_frame then
            return
        end
        self:update_fast(clock_ms)
        --检查信号
        if self:check_signal(scheduler) then
            return
        end
        --秒更新
        local now = now_ms // 1000
        if now == hive.now then
            return
        end
        hive.now = now
        self:update_second(clock_ms)
        self:update_by_time(now, clock_ms)
    end)
end

function UpdateMgr:update_by_time(now, clock_ms)
    --5秒更新
    local time = odate("*t", now)
    if time.sec % 5 > 0 then
        return
    end
    for obj, key in pairs(self.second5_objs) do
        thread_mgr:entry(key, function()
            obj:on_second5(clock_ms)
        end)
    end
    if self.hotfix_able then
        self:check_hotfix()
    end
    --30秒更新
    if time.sec % 30 > 0 then
        return
    end
    for obj, key in pairs(self.second30_objs) do
        thread_mgr:entry(key, function()
            obj:on_second30(clock_ms)
        end)
    end
    --检测停服
    self:check_service_stop()
    --执行gc
    collectgarbage("step", gc_step)
    --分更新
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
    --每日4点执行一次全量更新
    if cur_hour == 4 then
        collectgarbage("collect")
    end
    log_info("[UpdateMgr][update]now lua mem: %s m", collectgarbage("count") / 1024)
end

function UpdateMgr:check_service_stop()
    if not WTITLE and hive.service_status > ServiceStatus.RUN then
        if hive.safe_stop and event_mgr:fire_vote("vote_stop_service") then
            log_err("[UpdateMgr][check_service_stop] all vote agree,will stop service:%s", hive.name)
            signal_quit()
        end
    end
end

function UpdateMgr:check_signal(scheduler)
    if scheduler then
        local signal = sig_get()
        if sig_reload(signal) then
            self:check_hotfix()
            --通知woker更新
            scheduler:broadcast("on_reload")
        end
        if sig_check(signal) then
            if hive.run then
                hive.run = nil
                log_info("[UpdateMgr][check_signal]service quit for signal !")
                for obj in pairs(self.quit_objs) do
                    thread_mgr:fork(function()
                        obj:on_quit()
                    end)
                end
                --通知woker退出
                scheduler:quit()
            end
            return true
        end
    end
    return false
end

--检查文件更新
function UpdateMgr:check_hotfix()
    if hive.reload() > 0 then
        local config_mgr = hive.load("config_mgr")
        if config_mgr then
            config_mgr:reload(true)
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
        log_warn("[UpdateMgr][attach_hour] obj(%s) isn't on_hour method!", obj:source())
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
        log_warn("[UpdateMgr][attach_minute] obj(%s) isn't on_minute method!", obj:source())
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
        log_warn("[UpdateMgr][attach_second] obj(%s) isn't on_second method!", obj:source())
        return
    end
    self.second_objs[obj] = guid_new()
end

function UpdateMgr:detach_second(obj)
    self.second_objs[obj] = nil
end

--添加对象到5秒更新循环
function UpdateMgr:attach_second5(obj)
    if not obj.on_second5 then
        log_warn("[UpdateMgr][attach_second5] obj(%s) isn't on_second5 method!", obj:source())
        return
    end
    self.second5_objs[obj] = guid_new()
end

function UpdateMgr:detach_second5(obj)
    self.second5_objs[obj] = nil
end

--添加对象到30秒更新循环
function UpdateMgr:attach_second30(obj)
    if not obj.on_second30 then
        log_warn("[UpdateMgr][attach_second30] obj(%s) isn't on_second30 method!", obj:source())
        return
    end
    self.second30_objs[obj] = guid_new()
end

function UpdateMgr:detach_second30(obj)
    self.second30_objs[obj] = nil
end

--添加对象到帧更新循环
function UpdateMgr:attach_frame(obj)
    if not obj.on_frame then
        log_warn("[UpdateMgr][attach_frame] obj(%s) isn't on_frame method!", obj:source())
        return
    end
    self.frame_objs[obj] = guid_new()
end

function UpdateMgr:detach_frame(obj)
    self.frame_objs[obj] = nil
end

--添加对象到快帧更新循环
function UpdateMgr:attach_fast(obj)
    if not obj.on_fast then
        log_warn("[UpdateMgr][attach_fast] obj(%s) isn't on_fast method!", obj:source())
        return
    end
    self.fast_objs[obj] = guid_new()
end

function UpdateMgr:detach_fast(obj)
    self.fast_objs[obj] = nil
end

--添加对象到程序退出通知列表
function UpdateMgr:attach_quit(obj)
    if not obj.on_quit then
        log_warn("[UpdateMgr][attach_quit] obj(%s) isn't on_quit method!", obj:source())
        return
    end
    self.quit_objs[obj] = true
end

function UpdateMgr:detach_quit(obj)
    self.quit_objs[obj] = nil
end

hive.update_mgr = UpdateMgr()

return UpdateMgr
