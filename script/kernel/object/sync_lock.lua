--sync_lock.lua
--[[提供协程同步锁功能
示例:
    local lock<close> = thread_mgr:lock(key)
    ...
--]]
local co_running   = coroutine.running

local SECOND_10_MS = hive.enum("PeriodTime", "SECOND_10_MS")

local SyncLock     = class()
local prop         = property(SyncLock)
prop:reader("thread_mgr", nil)
prop:reader("timeout", 0)
prop:reader("count", 1)
prop:reader("key", nil)
prop:reader("co", nil)
prop:reader("yield",false)

function SyncLock:__init(thread_mgr, key,yield)
    self.thread_mgr = thread_mgr
    self.timeout    = hive.clock_ms + SECOND_10_MS
    self.co         = co_running()
    self.key        = key
    self.yield      = yield
end

function SyncLock:increase()
    self.count = self.count + 1
end

function SyncLock:unlock()
    self.count = self.count - 1
    if self.count == 0 then
        self.thread_mgr:unlock(self.key)
    end
end

function SyncLock:__defer()
    self:unlock()
end

return SyncLock
