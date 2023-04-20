-- cache_obj.lua
-- cache的实体类
local VarLock       = import("kernel/object/var_lock.lua")

local log_err       = logger.err
local log_debug     = logger.debug
local check_failed  = hive.failed
local check_success = hive.success

local KernCode      = enum("KernCode")
local CacheCode     = enum("CacheCode")
local DB_TIMEOUT    = hive.enum("NetwkTime", "DB_CALL_TIMEOUT")
local SUCCESS       = KernCode.SUCCESS
local thread_mgr    = hive.get("thread_mgr")
local CacheRow      = import("cache/cache_row.lua")

local CacheObj      = class()
local prop          = property(CacheObj)
prop:accessor("holding", true)          -- holding status
prop:accessor("lock_node_id", 0)        -- lock node id
prop:accessor("expire_time", 600)       -- expire time
prop:accessor("store_time", 300)        -- store time
prop:accessor("store_count", 200)       -- store count
prop:accessor("cache_name", "")         -- cache name
prop:accessor("primary_value", nil)     -- primary value
prop:accessor("cache_rows", {})         -- cache rows
prop:accessor("update_count", 0)        -- update count
prop:accessor("update_time", 0)         -- update time
prop:accessor("flush_time", 0)          -- flush time
prop:accessor("active_tick", 0)         -- active tick
prop:accessor("db_name", "")            -- db name
prop:accessor("records", {})            -- records
prop:accessor("dirty_records", {})      -- dirty records
prop:accessor("is_doing", false)        -- in doing

function CacheObj:__init(cache_conf, primary_value)
    self.primary_value = primary_value
    self.cache_rows    = cache_conf.rows
    self.db_name       = cache_conf.cache_db
    self.cache_name    = cache_conf.cache_name
    self.expire_time   = cache_conf.expire_time * 1000
    self.store_time    = cache_conf.store_time * 1000
    self.store_count   = cache_conf.store_count
    self.flush_time    = cache_conf.flush_time * 1000
end

function CacheObj:load()
    self.active_tick = hive.clock_ms
    self.update_time = hive.clock_ms
    for _, row_conf in pairs(self.cache_rows) do
        local tab_name         = row_conf.cache_table
        local record           = CacheRow(row_conf, self.primary_value)
        self.records[tab_name] = record
        local code             = record:load(self.db_name)
        if check_failed(code) then
            log_err("[CacheObj][load] load row failed: tab_name=%s", tab_name)
            return code
        end
    end
    self.holding = false
    log_debug("[CacheObj][load] %s,cost time:%s", self.cache_name, hive.clock_ms - self.update_time)
    return SUCCESS
end

--异步
function CacheObj:load_async()
    self.active_tick = hive.clock_ms
    self.update_time = hive.clock_ms
    local tab_cnt    = 0
    local ret        = SUCCESS
    local session_id = thread_mgr:build_session_id()
    for _, row_conf in pairs(self.cache_rows) do
        tab_cnt = tab_cnt + 1
        thread_mgr:fork(function()
            local tab_name         = row_conf.cache_table
            local record           = CacheRow(row_conf, self.primary_value)
            self.records[tab_name] = record
            local code             = record:load(self.db_name)
            if check_failed(code) then
                log_err("[CacheObj][load] load row failed: tab_name=%s", tab_name)
                thread_mgr:response(session_id, false, code)
                return
            end
            thread_mgr:response(session_id, true, code)
        end)
    end
    while tab_cnt > 0 do
        local ok, code = thread_mgr:yield(session_id, "load_async", DB_TIMEOUT)
        if check_failed(code, ok) then
            log_err("[CacheObj][load] load response:%s,%s", ok, code)
            ret = code
        end
        tab_cnt = tab_cnt - 1
    end
    log_debug("[CacheObj][load_async] %s,cost time:%s", self.cache_name, hive.clock_ms - self.update_time)
    self.holding = false
    return ret
end

function CacheObj:active()
    self.active_tick = hive.clock_ms
end

function CacheObj:pack()
    local res = {}
    for tab_name, record in pairs(self.records) do
        res[tab_name] = record:get_data()
    end
    return res
end

function CacheObj:is_dirty()
    return next(self.dirty_records)
end

function CacheObj:expired(tick, flush)
    if next(self.dirty_records) then
        return false
    end
    local escape_time = tick - self.active_tick
    if self.flush_time > 0 and escape_time > self.flush_time then
        return true
    end
    if self.lock_node_id == 0 and escape_time > self.expire_time then
        return true
    end
    return flush
end

function CacheObj:need_save(now)
    if self.is_doing then
        return false
    end
    if self.store_count <= self.update_count or self.update_time + self.store_time < now then
        return true
    end
    return false
end

function CacheObj:save()
    local _lock<close> = VarLock(self, "is_doing")
    self.active_tick   = hive.clock_ms
    if next(self.dirty_records) then
        self.update_count = 0
        self.update_time  = hive.clock_ms
        for record in pairs(self.dirty_records) do
            if check_success(record:save()) then
                self.dirty_records[record] = nil
            end
        end
        if next(self.dirty_records) then
            return false
        end
    end
    return true
end

function CacheObj:update(tab_name, tab_data, flush)
    local record = self.records[tab_name]
    if not record then
        log_err("[CacheObj][update] cannot find record! cache:%s, table:%s", self.cache_name, tab_name)
        return CacheCode.CACHE_KEY_IS_NOT_EXIST
    end
    self:active()
    self.update_count = self.update_count + 1
    local code        = record:update(tab_data, flush)
    if record:is_dirty() then
        self.dirty_records[record] = true
    end
    return code
end

function CacheObj:update_key(tab_name, table_kvs, flush)
    local record = self.records[tab_name]
    if not record then
        log_err("[CacheObj][update_key] cannot find record! cache:%s, table:%s", self.cache_name, tab_name)
        return CacheCode.CACHE_KEY_IS_NOT_EXIST
    end
    self:active()
    self.update_count = self.update_count + 1
    local code        = record:update_key(table_kvs, flush)
    if record:is_dirty() then
        self.dirty_records[record] = true
    end
    return code
end

return CacheObj
