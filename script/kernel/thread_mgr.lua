--thread_mgr.lua
local select        = select
local tunpack       = table.unpack
local tsize         = table_ext.size
local sformat       = string.format
local co_yield      = coroutine.yield
local co_create     = coroutine.create
local co_resume     = coroutine.resume
local co_running    = coroutine.running
local qxpcall       = hive.xpcall
local log_err       = logger.err

local QueueFIFO     = import("container/queue_fifo.lua")
local SyncLock      = import("kernel/object/sync_lock.lua")

local MINUTE_10_MS  = hive.enum("PeriodTime", "MINUTE_10_MS")

local ThreadMgr = singleton()
local prop = property(ThreadMgr)
prop:reader("session_id", 1)
prop:reader("coroutine_map", {})
prop:reader("syncqueue_map", {})
prop:reader("coroutine_pool", nil)

function ThreadMgr:__init()
    self.coroutine_pool = QueueFIFO()
end

function ThreadMgr:size()
    local co_cur_max = self.coroutine_pool:size()
    local co_cur_size = tsize(self.coroutine_map) + 1
    return co_cur_size, co_cur_max
end

function ThreadMgr:lock(key, to)
    local queue = self.syncqueue_map[key]
    if not queue then
        queue = QueueFIFO()
        self.syncqueue_map[key] = queue
    end
    queue.ttl = hive.clock_ms
    local head = queue:head()
    if not head then
        local lock = SyncLock(self, key, to)
        queue:push(lock)
        return lock
    else
        if head.co == co_running() then
            --防止重入
            head:increase()
            return head
        end
        local lock = SyncLock(self, key, to)
        queue:push(lock)
        co_yield()
        return lock
    end
end

function ThreadMgr:unlock(key)
    local queue = self.syncqueue_map[key]
    if queue then
        queue:pop()
        if queue:empty() then
            return
        end
        local lock = queue:pop()
        co_resume(lock.co)
    end
end

function ThreadMgr:co_create(f)
    local pool = self.coroutine_pool
    local co = pool:pop()
    if co == nil then
        co = co_create(function(...)
            qxpcall(f, "[ThreadMgr][co_create] fork error: %s", ...)
            while true do
                f = nil
                pool:push(co)
                f = co_yield()
                if type(f) == "function" then
                    qxpcall(f, "[ThreadMgr][co_create] fork error: %s", co_yield())
                end
            end
        end)
    else
        co_resume(co, f)
    end
    return co
end

function ThreadMgr:response(session_id, ...)
    local context = self.coroutine_map[session_id]
    if not context then
        log_err("[ThreadMgr][response] unknown session_id(%s) response!", session_id)
        return
    end
    self.coroutine_map[session_id] = nil
    self:resume(context.co, ...)
end

function ThreadMgr:resume(co, ...)
    return co_resume(co, ...)
end

function ThreadMgr:yield(session_id, title, ms_to, ...)
    local context = {co = co_running(), title = title, to = hive.clock_ms + ms_to}
    self.coroutine_map[session_id] = context
    return co_yield(...)
end

function ThreadMgr:on_minute(clock_ms)
    for key, queue in pairs(self.syncqueue_map) do
        if queue:empty() and clock_ms - queue.ttl > MINUTE_10_MS then
            self.syncqueue_map[key] = nil
        end
    end
end

function ThreadMgr:on_second(clock_ms)
    --处理锁超时
    for _, queue in pairs(self.syncqueue_map) do
        local head = queue:head()
        if head and head.timeout <= clock_ms then
            head:unlock()
        end
    end
    --检查协程超时
    local timeout_coroutines = {}
    for session_id, context in pairs(self.coroutine_map) do
        if context.to <= clock_ms then
            timeout_coroutines[#timeout_coroutines + 1] = session_id
        end
    end
    --处理协程超时
    for _, session_id in pairs(timeout_coroutines) do
        local context = self.coroutine_map[session_id]
        if context then
            self.coroutine_map[session_id] = nil
            if context.title then
                log_err("[ThreadMgr][on_second] session_id(%s:%s) timeout!", session_id, context.title)
            end
            self:resume(context.co, false, sformat("%s timeout", context.title), session_id)
        end
    end
end

function ThreadMgr:fork(f, ...)
    local n = select("#", ...)
    local co
    if n == 0 then
        co = self:co_create(f)
    else
        local args = { ... }
        co = self:co_create(function() f(tunpack(args, 1, n)) end)
    end
    self:resume(co, ...)
    return co
end

function ThreadMgr:sleep(ms)
    local session_id = self:build_session_id()
    self:yield(session_id, nil, ms)
end

function ThreadMgr:build_session_id()
    self.session_id = self.session_id + 1
    if self.session_id >= 0x7fffffff then
        self.session_id = 1
    end
    return self.session_id
end

function ThreadMgr:success_call(period, success_func, try_time)
    self:fork(function()
        try_time = try_time or 10
        while true do
            if success_func() or try_time <= 0 then
                break
            end
            try_time = try_time - 1
            self:sleep(period)
        end
    end)
end

hive.thread_mgr = ThreadMgr()

return ThreadMgr
