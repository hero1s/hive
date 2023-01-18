--thread_mgr.lua
local select     = select
local tunpack    = table.unpack
local tsort      = table.sort
local tsize      = table_ext.size
local sformat    = string.format
local co_yield   = coroutine.yield
local co_create  = coroutine.create
local co_resume  = coroutine.resume
local co_running = coroutine.running
local mabs       = math.abs
local hxpcall    = hive.xpcall
local log_err    = logger.err
local log_info   = logger.info

local QueueFIFO  = import("container/queue_fifo.lua")

local ThreadMgr  = singleton()
local prop       = property(ThreadMgr)
prop:reader("session_id", 1)
prop:reader("coroutine_map", {})
prop:reader("syncqueue_map", {})
prop:reader("coroutine_pool", nil)

local function sync_queue()
    local current_thread
    local ref          = 0
    local thread_queue = QueueFIFO()

    local scope        = setmetatable({}, { __close = function()
        ref = ref - 1
        if ref == 0 then
            current_thread = thread_queue:pop()
            if current_thread then
                co_resume(current_thread)
            end
        end
    end })

    return function(refcount)
        if refcount then
            return ref
        end
        local thread = co_running()
        if current_thread and current_thread ~= thread then
            thread_queue:push(thread)
            co_yield()
            assert(ref == 0)    -- current_thread == thread
        end
        current_thread = thread
        ref            = ref + 1
        return scope
    end
end

function ThreadMgr:__init()
    self.coroutine_pool = QueueFIFO()
end

function ThreadMgr:size()
    local co_cur_max  = self.coroutine_pool:size()
    local co_cur_size = tsize(self.coroutine_map) + 1
    return co_cur_size, co_cur_max
end

function ThreadMgr:lock_size()
    local count = 0
    for _, v in pairs(self.syncqueue_map) do
        count = count + v(true)
    end
    return count
end

function ThreadMgr:lock(key, no_reentry)
    local queue = self.syncqueue_map[key]
    if not queue then
        queue                   = sync_queue()
        self.syncqueue_map[key] = queue
    end
    if no_reentry and queue(true) > 0 then
        log_err("[ThreadMgr][lock] the function is repeat call,please check is right!:%s", key)
        return nil
    end
    return queue()
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
    local context                  = { co = co_running(), title = title, to = hive.clock_ms + ms_to }
    self.coroutine_map[session_id] = context
    return co_yield(...)
end

function ThreadMgr:get_title(session_id)
    local context = self.coroutine_map[session_id]
    if context then
        return context.title
    end
    return nil
end

function ThreadMgr:on_minute(clock_ms)
    for key, queue in pairs(self.syncqueue_map) do
        if queue(true) == 0 then
            log_info("[ThreadMgr][on_minute] remove lock:%s", key)
            self.syncqueue_map[key] = nil
        end
    end
end

function ThreadMgr:on_second(clock_ms)

end

local MAX_DIFF_ID<const> = 100000000 --1亿
function ThreadMgr:on_fast(clock_ms)
    --检查协程超时
    local timeout_coroutines = {}
    for session_id, context in pairs(self.coroutine_map) do
        if context.to <= clock_ms then
            timeout_coroutines[#timeout_coroutines + 1] = session_id
        end
    end
    --处理协程超时
    tsort(timeout_coroutines, function(a, b)
        if mabs(a - b) < MAX_DIFF_ID then
            return a > b
        end
        return a < b
    end)
    for _, session_id in pairs(timeout_coroutines) do
        local context = self.coroutine_map[session_id]
        if context then
            self.coroutine_map[session_id] = nil
            if context.title then
                log_info("[ThreadMgr][on_fast] session_id(%s:%s) timeout!", session_id, context.title)
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
        co         = self:co_create(function()
            f(tunpack(args, 1, n))
        end)
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
