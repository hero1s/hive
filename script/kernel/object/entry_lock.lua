--entry_lock.lua
--[[入口锁
示例:
    thread_mgr:entry(key, func)
    ...
--]]

local EntryLock = class()
local prop = property(EntryLock)
prop:reader("thread_mgr", nil)
prop:reader("key", nil)

function EntryLock:__init(thread_mgr, key)
    self.thread_mgr = thread_mgr
    self.key = key
end

function EntryLock:unlock()
    self.thread_mgr:leave(self.key)
end

function EntryLock:__defer()
    self:unlock()
end

return EntryLock
