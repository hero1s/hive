
local QueueLRU   = import("container/queue_lru.lua")
local log_debug  = logger.debug

local thread_mgr = hive.get("thread_mgr")

local a          = { a = 1, c = { a = 2 } }

local cache      = lcache.new(5)
local lua_cache  = QueueLRU(500000)
local function test_gc(cache_type)
    log_debug("test gc %s", cache_type)
    if cache_type == "lua" then
        for i = 1, 500000 do
            lua_cache:set(i, a)
        end
    else
        cache = lcache.new(500000)
        for i = 1, 500000 do
            cache:put(i, a)
        end
    end
    local gc_mgr = hive.get("gc_mgr")
    gc_mgr:full_gc()
end

thread_mgr:fork(function()
    for i = 1, 10 do
        cache:put(i, a)
        log_debug("size-> %d,value:%s", cache:size(), cache:get(i))
    end
    for i = 1, 10 do
        log_debug("%s exist-> %s,value:%s", i, cache:exist(i), cache:get(i))
    end

    test_gc("lua")
    --test_gc("cpp")
    thread_mgr:sleep(2000)
end)




