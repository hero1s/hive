--clock_mgr.lua
local ltimer = require("ltimer")

import("kernel/thread_mgr.lua")
import("kernel/timer_mgr.lua")
import("kernel/clock_mgr.lua")
local env_number     = environ.number

local pairs          = pairs
local log_info       = logger.info
local log_warn       = logger.warn
local ltime          = ltimer.time
local sig_check      = signal.check
local collectgarbage = collectgarbage

local timer_mgr      = hive.get("timer_mgr")
local clock_mgr      = hive.get("clock_mgr")
local thread_mgr     = hive.get("thread_mgr")

local HALF_MS        = hive.enum("PeriodTime", "HALF_MS")
local HOUR_MS        = hive.enum("PeriodTime", "HOUR_MS")
local FRAME_MS       = hive.enum("PeriodTime", "FRAME_MS")
local SECOND_MS      = hive.enum("PeriodTime", "SECOND_MS")
local MINUTE_MS      = hive.enum("PeriodTime", "MINUTE_MS")
local SECOND_2_MS    = hive.enum("PeriodTime", "SECOND_2_MS")

local UpdateMgr      = singleton()
local prop           = property(UpdateMgr)
prop:reader("gc_id", 0)
prop:reader("hour_id", 0)
prop:reader("frame_id", 0)
prop:reader("second_id", 0)
prop:reader("minute_id", 0)
prop:reader("reload_id", 0)
prop:reader("quit_objs", {})
prop:reader("hour_objs", {})
prop:reader("frame_objs", {})
prop:reader("second_objs", {})
prop:reader("minute_objs", {})
function UpdateMgr:__init()
    self.is_open_reload = env_number("HIVE_OPEN_RELOAD", 0)
    self:setup()
end

function UpdateMgr:setup()
    local now_ms   = ltime()
    self.gc_id     = clock_mgr:alarm(SECOND_2_MS, now_ms)
    self.hour_id   = clock_mgr:alarm(HOUR_MS, now_ms)
    self.frame_id  = clock_mgr:alarm(FRAME_MS, now_ms)
    self.second_id = clock_mgr:alarm(SECOND_MS, now_ms)
    self.minute_id = clock_mgr:alarm(MINUTE_MS, now_ms)
    self.reload_id = clock_mgr:alarm(SECOND_2_MS, now_ms)
    --注册订阅
    self:attach_quit(timer_mgr)
    self:attach_quit(clock_mgr)
    self:attach_frame(timer_mgr)
    self:attach_second(thread_mgr)
    self:attach_minute(thread_mgr)
    collectgarbage("generational")
end

function UpdateMgr:update(now_ms, count)
    --业务更新
    thread_mgr:fork(function()
        local clock_ms, frame = clock_mgr:check(self.frame_id, now_ms)
        if not clock_ms then
            return
        end
        if clock_ms > HALF_MS then
            log_warn("[hive][update] warning clock_ms(%d) too long count(%d)!", clock_ms, count)
        end
        --帧更新
        hive.frame = frame
        for obj in pairs(self.frame_objs) do
            obj:on_frame(now_ms, frame)
        end
        --秒更新
        if not clock_mgr:check(self.second_id, now_ms) then
            return
        end
        for obj in pairs(self.second_objs) do
            obj:on_second(now_ms)
        end
        --gc更新
        if clock_mgr:check(self.gc_id, now_ms) then
            collectgarbage("step", 1)
        end
        --热更新
        if self.is_open_reload == 1 and clock_mgr:check(self.reload_id, now_ms) then
            hive.reload()
        end
        --检查信号
        if sig_check() then
            self:quit()
        end
        --分更新
        if not clock_mgr:check(self.minute_id, now_ms) then
            return
        end
        for obj in pairs(self.minute_objs) do
            obj:on_minute(now_ms)
        end
        --时更新
        if not clock_mgr:check(self.hour_id, now_ms) then
            return
        end
        for obj in pairs(self.hour_objs) do
            obj:on_hour(now_ms)
        end
        --gc
        collectgarbage("collect")
    end)
end

function UpdateMgr:quit()
    for obj in pairs(self.quit_objs) do
        obj:on_quit()
    end
    log_info("[UpdateMgr][quit]service quit for signal !")
    hive.run = nil
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

hive.update_mgr = UpdateMgr()

return UpdateMgr
