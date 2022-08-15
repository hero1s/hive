--clock_mgr.lua
local lhelper        = require("lhelper")
local mem_usage      = lhelper.mem_usage

local pairs          = pairs
local odate          = os.date
local otime          = os.time
local log_info       = logger.info
local log_warn       = logger.warn
local log_err        = logger.err
local sig_check      = signal.check
local collectgarbage = collectgarbage
local cut_tail       = math_ext.cut_tail

local timer_mgr      = hive.get("timer_mgr")
local thread_mgr     = hive.get("thread_mgr")

local HALF_MS        = hive.enum("PeriodTime", "HALF_MS")
local SECOND_5_MS    = hive.enum("PeriodTime", "SECOND_5_MS")

local UpdateMgr      = singleton()
local prop           = property(UpdateMgr)
prop:reader("last_day", 0)
prop:reader("last_hour", 0)
prop:reader("last_minute", 0)
prop:reader("max_mem_usage", 0)
prop:reader("quit_objs", {})
prop:reader("hour_objs", {})
prop:reader("frame_objs", {})
prop:reader("second_objs", {})
prop:reader("minute_objs", {})

function UpdateMgr:__init()
    --注册订阅
    self:attach_quit(timer_mgr)
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
        --秒更新
        local now     = otime()
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
    if sig_check() then
        log_info("[UpdateMgr][sig_check]service quit for signal !")
        for obj in pairs(self.quit_objs) do
            obj:on_quit()
        end
        hive.run = nil
    end
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
    local mem = cut_tail(mem_usage(),2)
    if mem > self.max_mem_usage then
        self.max_mem_usage = mem
        self.lua_mem_usage = cut_tail(collectgarbage("count") / 1024,2)
        log_warn("UpdateMgr][monitor_mem] memory:%s M,lua_mem: %s M,threads:%s/%s", self.max_mem_usage, self.lua_mem_usage,thread_mgr:size())
    else
        log_info("UpdateMgr][monitor_mem] memory:%s M,lua_mem: %s M,threads:%s/%s", self.max_mem_usage, self.lua_mem_usage,thread_mgr:size())
    end
end

hive.update_mgr = UpdateMgr()

return UpdateMgr
