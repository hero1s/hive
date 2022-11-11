--clock_mgr.lua
local lhelper        = require("lhelper")
local mem_usage      = lhelper.mem_usage

local pairs          = pairs
local odate          = os.date
local log_info       = logger.info
local log_warn       = logger.warn
local log_err        = logger.err
local sig_check      = signal.check
local collectgarbage = collectgarbage
local cut_tail       = math_ext.cut_tail
local is_same_day    = datetime_ext.is_same_day

local timer_mgr      = hive.get("timer_mgr")
local thread_mgr     = hive.get("thread_mgr")
local event_mgr      = hive.get("event_mgr")

local HALF_MS        = hive.enum("PeriodTime", "HALF_MS")
local SECOND_5_MS    = hive.enum("PeriodTime", "SECOND_5_MS")

local UpdateMgr      = singleton()
local prop           = property(UpdateMgr)
prop:reader("last_day", 0)
prop:reader("last_hour", 0)
prop:reader("last_minute", 0)
prop:reader("last_check_time", 0)
prop:reader("max_mem_usage", 0)
prop:reader("max_lua_mem_usage", 0)
prop:reader("quit_objs", {})
prop:reader("hour_objs", {})
prop:reader("frame_objs", {})
prop:reader("second_objs", {})
prop:reader("minute_objs", {})
prop:reader("next_events", {})
prop:reader("next_handlers", {})

function UpdateMgr:__init()
    --注册订阅
    self:attach_frame(timer_mgr)
    self:attach_second(thread_mgr)
    self:attach_minute(thread_mgr)
    --注册5秒定时器
    self.open_reload = environ.number("HIVE_OPEN_RELOAD", 0)
    timer_mgr:loop(SECOND_5_MS, function()
        self:on_second_5s()
    end)
    --开启分代gc
    collectgarbage("generational")
end

function UpdateMgr:on_second_5s()
    --执行gc
    collectgarbage("step", 5)
    --检查文件更新
    if self.open_reload == 1 then
        if hive.reload() > 0 then
            local config_mgr = hive.get("config_mgr")
            config_mgr:reload()
        end
    end
end

function UpdateMgr:update_next()
    for _, handler in pairs(self.next_handlers) do
        thread_mgr:fork(handler)
    end
    self.next_handlers = {}
    for key, events in pairs(self.next_events) do
        for event, arg in pairs(events) do
            thread_mgr:fork(function()
                event_mgr:notify_trigger(event, key, arg)
            end)
        end
    end
    self.next_events = {}
end

function UpdateMgr:update(now_ms, clock_ms)
    --业务更新
    thread_mgr:fork(function()
        local diff_ms = clock_ms - hive.clock_ms
        if diff_ms > HALF_MS and hive.frame > 1 then
            log_err("[UpdateMgr][update] last frame exec too long(%d ms)!,service:%s", diff_ms, hive.name)
        end
        --帧更新
        local frame = hive.frame + 1
        for obj in pairs(self.frame_objs) do
            obj:on_frame(clock_ms, frame)
        end
        hive.frame    = frame
        hive.now_ms   = now_ms
        hive.clock_ms = clock_ms
        --更新帧逻辑
        self:update_next()
        --秒更新
        local now = now_ms // 1000
        if now == hive.now then
            return
        end
        hive.now = now
        for obj in pairs(self.second_objs) do
            obj:on_second(clock_ms)
        end
        --检查信号
        self:sig_check()
        --分更新
        local time = odate("*t", now)
        if time.min == self.last_minute then
            return
        end
        self.last_minute = time.min
        for obj in pairs(self.minute_objs) do
            obj:on_minute(clock_ms)
        end
        self:check_new_day()
        self:monitor_mem()
        --时更新
        if time.hour == self.last_hour then
            return
        end
        self.last_hour = time.hour
        for obj in pairs(self.hour_objs) do
            obj:on_hour(clock_ms, time.hour)
        end
        --gc
        collectgarbage("collect")
    end)
end

function UpdateMgr:sig_check()
    if sig_check and sig_check() then
        log_info("[UpdateMgr][sig_check]service quit for signal !")
        for obj in pairs(self.quit_objs) do
            obj:on_quit()
        end
        hive.run = nil
    end
end

function UpdateMgr:check_new_day()
    if self.last_check_time > 0 and self.last_check_time < hive.now then
        if not is_same_day(self.last_check_time, hive.now) then
            log_warn("[UpdateMgr][check_new_day] notify [%s] this time is new day!!!", hive.name)
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

--下一帧执行一个函数
function UpdateMgr:attach_next(key, func)
    self.next_handlers[key] = func
end

--下一帧执行一个事件
function UpdateMgr:attach_event(key, event, arg)
    local events = self.next_events[key]
    if not events then
        self.next_events[key] = { [event] = arg }
        return
    end
    events[event] = arg
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
    local mem     = cut_tail(mem_usage(), 1)
    local lua_mem = cut_tail(collectgarbage("count") / 1024, 1)
    if mem > self.max_mem_usage then
        self.max_mem_usage = mem
    end
    if lua_mem > self.max_lua_mem_usage then
        self.max_lua_mem_usage = lua_mem
    end
    log_info("UpdateMgr][monitor_mem] mem:%s/%s M,lua_mem: %s/%s M,threads:%s/%s",
             mem, self.max_mem_usage, lua_mem, self.max_lua_mem_usage, thread_mgr:size())
end

hive.update_mgr = UpdateMgr()

return UpdateMgr
