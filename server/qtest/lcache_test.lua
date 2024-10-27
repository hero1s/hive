local QueueLRU   = import("container/queue_lru.lua")
local CacheMap   = import("container/cache_map.lua")
local log_debug  = logger.debug

local thread_mgr = hive.get("thread_mgr")

local a          = { a = 1, c = { a = 2 } }

local cache      = CacheMap(5)
local lua_cache  = QueueLRU(500000)
local function test_gc(cache_type)
    log_debug("test gc %s", cache_type)
    if cache_type == "lua" then
        for i = 1, 500000 do
            lua_cache:set(i, a)
        end
    else
        cache = CacheMap(500000)
        for i = 1, 500000 do
            cache:set(i, a)
        end
    end
    local gc_mgr = hive.get("gc_mgr")
    gc_mgr:full_gc()
end

thread_mgr:fork(function()
    for i = 1, 10 do
        cache:set(i, a)
        log_debug("size-> %d,value:%s", cache:size(), cache:get(i))
    end
    for i = 1, 10 do
        log_debug("%s del-> %s,size:%s", i, cache:del(i), cache:size())
        log_debug("size-> %d,value:%s", cache:size(), cache:get(i))
    end
    for i = 1, 10 do
        log_debug("%s exist-> %s,value:%s", i, cache:exist(i), cache:get(i))
    end

    test_gc("lua")
    test_gc("cpp")
    thread_mgr:sleep(2000)
end)

local function test_table_size()
    local TableMem  = import("feature/table_mem.lua")
    local table_mem = TableMem(3, 0)
    local testa     = { a = 1, b = 2, c = 3, d = { 1, 2, 3 }, e = { a = 1, b = 2, c = { 1, 2, 3 } } }
    table_mem:table_size_dump(testa, "testa")
end

test_table_size()

