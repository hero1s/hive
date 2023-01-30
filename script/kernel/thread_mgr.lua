--thread_mgr.lua
local select       = select
local tunpack      = table.unpack
local sformat      = string.format
local co_yield     = coroutine.yield
local co_create    = coroutine.create
local co_resume    = coroutine.resume
local co_running   = coroutine.running

local mrandom      = math_ext.random
local tsize        = table_ext.size
local hxpcall      = hive.xpcall
local log_err      = logger.err
local log_info     = logger.info

local QueueFIFO    = import("container/queue_fifo.lua")
local SyncLock     = import("kernel/object/sync_lock.lua")

local MINUTE_10_MS = hive.enum("PeriodTime", "MINUTE_10_MS")

local ThreadMgr    = singleton()
local prop         = property(ThreadMgr)
prop:reader("session_id", 1)
prop:reader("syncqueue_map", {})
prop:reader("coroutine_waitings", {})
prop:reader("coroutine_yields", {})
prop:reader("coroutine_pool", nil)

function ThreadMgr:__init()
    self.session_id     = mrandom()
    self.coroutine_pool = QueueFIFO()
end

function ThreadMgr:size()
    local co_idle_size  = self.coroutine_pool:size()
    local co_yield_size = tsize(self.coroutine_yields)
    local co_wait_size  = tsize(self.coroutine_waitings)
    return co_yield_size + co_wait_size + 1, co_idle_size
end

function ThreadMgr:lock_size()
    local count = 0
    for _, v in pairs(self.syncqueue_map) do
        count = count + v:size()
    end
    return count
end

function ThreadMgr:lock(key, waiting)
    local queue = self.syncqueue_map[key]
    if not queue then
        queue                   = QueueFIFO()
        self.syncqueue_map[key] = queue
    end
    queue.ttl  = hive.clock_ms + MINUTE_10_MS
    local head = queue:head()
    if not head then
        local lock = SyncLock(self, key)
        queue:push(lock)
        return lock
    else
        if head.co == co_running() then
            --防止重入
            log_info("[ThreadMgr][lock] the lock repeat lock:[%s],count:%s,queue:%s", key, head:get_count(), queue:size())
            head:increase()
            return head
        end
        if waiting or waiting == nil then
            --等待则挂起
            local lock = SyncLock(self, key)
            queue:push(lock)
            co_yield()
            return lock
        end
        log_err("[ThreadMgr][lock] the func is runing and try lock:[%s],check it's right", key)
    end
end

function ThreadMgr:unlock(key, force)
    local queue = self.syncqueue_map[key]
    if queue then
        local head = queue:head()
        if head then
            if head.co == co_running() or force then
                queue:pop()
                local next = queue:head()
                if next then
                    self.coroutine_waitings[next.co] = 0
                end
            end
        end
    end
end

function ThreadMgr:co_create(f)
    local pool = self.coroutine_pool
    local co   = pool:pop()
    if co == nil then
        co = co_create(function(...)
            hxpcall(f, "[ThreadMgr][co_create] fork error: %s", ...)
            while true do
                f = nil
                pool:push(co)
                f = co_yield()
                if type(f) == "function" then
                    hxpcall(f, "[ThreadMgr][co_create] fork error: %s", co_yield())
                end
            end
        end)
    else
        co_resume(co, f)
    end
    return co
end

function ThreadMgr:response(session_id, ...)
    local context = self.coroutine_yields[session_id]
    if not context then
        log_err("[ThreadMgr][response] unknown session_id(%s) response!", session_id)
        return
    end
    self.coroutine_yields[session_id] = nil
    self:resume(context.co, ...)
end

function ThreadMgr:resume(co, ...)
    return co_resume(co, ...)
end

function ThreadMgr:yield(session_id, title, ms_to, ...)
    local context                     = { co = co_running(), title = title, to = hive.clock_ms + ms_to }
    self.coroutine_yields[session_id] = context
    return co_yield(...)
end

function ThreadMgr:get_title(session_id)
    local context = self.coroutine_yields[session_id]
    if context then
        return context.title
    end
    return nil
end

function ThreadMgr:on_minute(clock_ms)
    for key, queue in pairs(self.syncqueue_map) do
        if queue:empty() and clock_ms > queue.ttl then
            self.syncqueue_map[key] = nil
        end
    end
end

function ThreadMgr:on_second(clock_ms)
    --处理锁超时
    for key, queue in pairs(self.syncqueue_map) do
        local head = queue:head()
        if head and head.timeout <= clock_ms then
            self:unlock(key, true)
            log_err("[ThreadMgr][on_second] the lock is timeout:%s,count:%s,cost:%s,queue:%s",
                    head.key, head.count, head:cost_time(clock_ms), queue:size())
        end
    end
    --检查协程超时
    local timeout_coroutines = {}
    for session_id, context in pairs(self.coroutine_yields) do
        if context.to <= clock_ms then
            timeout_coroutines[session_id] = context
        end
    end
    --处理协程超时
    for session_id, context in pairs(timeout_coroutines) do
        self.coroutine_yields[session_id] = nil
        if context.title then
            log_err("[ThreadMgr][on_fast] session_id(%s:%s) timeout!", session_id, context.title)
        end
        self:resume(context.co, false, sformat("%s timeout", context.title), session_id)
    end
end

function ThreadMgr:on_frame(clock_ms)
    --检查协程超时
    repeat
        local timeout_coroutines = {}
        for co, ms_to in pairs(self.coroutine_waitings) do
            if ms_to <= clock_ms then
                timeout_coroutines[#timeout_coroutines + 1] = co
            end
        end
        --处理协程超时
        if next(timeout_coroutines) then
            for _, co in pairs(timeout_coroutines) do
                self.coroutine_waitings[co] = nil
                co_resume(co)
            end
        else
            break
        end
    until(false)
end

function ThreadMgr:fork(f, ...)
    local n = select("#", ...)
    local co
    if n == 0 then
        co = self:co_create(f)
    else
        local args = { ... }
        co         = self:co_create(function()
            f(tunpack(args, 1, n))
        end)
    end
    self:resume(co, ...)
    return co
end

function ThreadMgr:sleep(ms)
    local co                    = co_running()
    self.coroutine_waitings[co] = hive.clock_ms + ms
    co_yield()
end

function ThreadMgr:build_session_id()
    self.session_id = self.session_id + 1
    if self.session_id >= 0x7fffffff then
        self.session_id = 1
    end
    return self.session_id
end

function ThreadMgr:success_call(period, success_func, delay, try_times)
    if delay and delay > 0 then
        self:sleep(delay)
    end
    self:fork(function()
        try_times = try_times or 10
        while true do
            if success_func() or try_times <= 0 then
                break
            end
            try_times = try_times - 1
            self:sleep(period)
        end
    end)
end

hive.thread_mgr = ThreadMgr()

return ThreadMgr
