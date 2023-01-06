-- cache_obj.lua
-- cache的实体类
local lcodec        = require("lcodec")
local log_err       = logger.err
local new_guid      = lcodec.guid_new
local check_failed  = hive.failed
local check_success = hive.success

local KernCode      = enum("KernCode")
local CacheCode     = enum("CacheCode")
local SUCCESS       = KernCode.SUCCESS

local mongo_mgr     = hive.get("mongo_mgr")

local CacheRow      = import("cache/cache_row.lua")

local CacheObj      = class()
local prop          = property(CacheObj)
prop:accessor("uuid", 0)                -- uuid
prop:accessor("flush", false)           -- flush status
prop:accessor("holding", true)          -- holding status
prop:accessor("cache_total", false)     -- cache total
prop:accessor("lock_node_id", 0)        -- lock node id
prop:accessor("expire_time", 600)       -- expire time
prop:accessor("store_time", 300)        -- store time
prop:accessor("store_count", 200)       -- store count
prop:accessor("cache_key", "")          -- cache key
prop:accessor("primary_value", nil)     -- primary value
prop:accessor("databese_mgr", nil)      -- databese mgr
prop:accessor("cache_table", "")        -- cache table
prop:accessor("cache_rows", {})         -- cache rows
prop:accessor("update_count", 0)        -- update count
prop:accessor("update_time", 0)         -- update time
prop:accessor("flush_time", 0)          -- flush time
prop:accessor("active_tick", 0)         -- active tick
prop:accessor("db_name", "")            -- db name
prop:accessor("records", {})            -- records
prop:accessor("dirty_records", {})      -- dirty records

function CacheObj:__init(cache_conf, primary_value)
    self.uuid          = new_guid()
    self.primary_value = primary_value
    self.cache_rows    = cache_conf.rows
    self.db_name       = cache_conf.cache_db
    self.cache_total   = cache_conf.cache_total
    self.cache_table   = cache_conf.cache_table
    self.cache_key     = cache_conf.cache_key
    self.expire_time   = cache_conf.expire_time * 1000
    self.store_time    = cache_conf.store_time * 1000
    self.store_count   = cache_conf.store_count
    self.flush_time    = cache_conf.flush_time * 1000
end

function CacheObj:info()
    return string.format("%s:%s,%s", self.cache_table, self.cache_key, self.primary_value)
end

function CacheObj:load()
    self.active_tick = hive.clock_ms
    self.update_time = hive.clock_ms
    if self.cache_total then
        --合并加载模式
        local query     = { [self.cache_key] = self.primary_value }
        local code, res = mongo_mgr:find_one(self.db_name, self.cache_table, query, { _id = 0 })
        if check_failed(code) then
            log_err("[CacheObj][load] failed: cache_table=%s,res=%s", self.cache_table, res)
            return code
        end
        for _, row_conf in pairs(self.cache_rows) do
            local tab_name         = row_conf.cache_table
            local record           = CacheRow(row_conf, self.primary_value, self.cache_table, res[tab_name])
            self.records[tab_name] = record
        end
        self.holding = false
        return code
    else
        --分散加载模式
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
        return SUCCESS
    end
end

function CacheObj:active()
    self.flush       = false
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

function CacheObj:expired(tick)
    if next(self.dirty_records) then
        return false
    end
    local escape_time = tick - self.active_tick
    if self.flush_time > 0 then
        return escape_time > self.flush_time
    end
    if not self.flush then
        return false
    end
    return escape_time > self.expire_time
end

function CacheObj:check_store(now)
    if self.store_count <= self.update_count or self.update_time + self.store_time < now then
        return self:save()
    end
    return false
end

function CacheObj:save()
    self.active_tick = hive.clock_ms
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
        log_err("[CacheObj][update] cannot find record! cache:%s, table:%s", self.cache_table, tab_name)
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
        log_err("[CacheObj][update_key] cannot find record! cache:%s, table:%s", self.cache_table, tab_name)
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
