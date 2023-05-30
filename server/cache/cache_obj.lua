-- cache_obj.lua
-- cache的实体类
local VarLock       = import("kernel/object/var_lock.lua")

local log_err       = logger.err
local log_info      = logger.info
local check_failed  = hive.failed
local check_success = hive.success

local KernCode      = enum("KernCode")
local CacheCode     = enum("CacheCode")
local SUCCESS       = KernCode.SUCCESS
local mongo_mgr     = hive.get("mongo_mgr")

local CacheObj      = class()
local prop          = property(CacheObj)
prop:accessor("holding", true)          -- holding status
prop:accessor("lock_node_id", 0)        -- lock node id
prop:accessor("expire_time", 600)       -- expire time
prop:accessor("store_time", 300)        -- store time
prop:accessor("store_count", 200)       -- store count
prop:accessor("cache_name", "")         -- cache name
prop:accessor("cache_table", nil)       -- cache table
prop:accessor("cache_key", "")          -- cache key
prop:accessor("primary_value", nil)     -- primary value
prop:accessor("update_count", 0)        -- update count
prop:accessor("update_time", 0)         -- update time
prop:accessor("active_tick", 0)         -- active tick
prop:accessor("db_name", "default")     -- database name
prop:accessor("dirty", false)           -- dirty
prop:accessor("fail_cnt", 0)            -- 存储失败次数
prop:accessor("retry_time", 0)          -- 重试时间
prop:accessor("data", {})               -- data
prop:accessor("is_doing", false)        -- in doing
prop:accessor("flush", false)
prop:reader("save_cnt", 0)

function CacheObj:__init(cache_conf, primary_value)
    self.primary_value = primary_value
    self.db_name       = cache_conf.cache_db
    self.cache_name    = cache_conf.cache_name
    self.cache_table   = cache_conf.cache_table
    self.cache_key     = cache_conf.cache_key
    self.expire_time   = cache_conf.expire_time * 1000
    self.store_time    = cache_conf.store_time * 1000
    self.store_count   = cache_conf.store_count
end

function CacheObj:load()
    self.active_tick = hive.clock_ms
    self.update_time = hive.clock_ms
    local query      = { [self.cache_key] = self.primary_value }
    local code, res  = mongo_mgr:find_one(self.db_name, self.cache_table, query, { _id = 0 })
    if check_failed(code) then
        log_err("[CacheRow][load] failed: %s=> db: %s, table: %s", res, self.db_name, self.cache_table)
        return code
    end
    self.data    = res
    self.holding = false
    return SUCCESS
end

function CacheObj:active()
    self.active_tick = hive.clock_ms
end

function CacheObj:pack()
    return self.data
end

function CacheObj:is_dirty()
    return self.dirty
end

function CacheObj:expired(clock_ms, flush)
    if self.dirty then
        return false
    end
    local escape_time = clock_ms - self.active_tick
    if escape_time > self.expire_time then
        return true
    end
    return flush
end

function CacheObj:need_save(clock_ms)
    if self.is_doing then
        return false
    end
    if self.flush then
        return true
    end
    if self.store_count <= self.update_count or self.update_time + self.store_time < clock_ms then
        return true
    end
    return false
end

function CacheObj:save()
    if self.is_doing then
        return false
    end
    local _lock<close> = VarLock(self, "is_doing")
    if self.dirty then
        if check_success(self:save_impl()) then
            self.flush = false
        end
    end
    return true
end

function CacheObj:save_impl()
    if self.dirty then
        if self.fail_cnt > 0 and hive.now < self.retry_time then
            return KernCode.MONGO_FAILED
        end
        local selector  = { [self.cache_key] = self.primary_value }
        local code, res = mongo_mgr:update(self.db_name, self.cache_table, self.data, selector, true)
        if check_failed(code) then
            self.fail_cnt   = self.fail_cnt + 1
            self.retry_time = hive.now + self.fail_cnt * 60
            log_err("[CacheObj][save_impl] failed: cnt:%s, %s=> db: %s, table: %s", self.fail_cnt, res, self.db_name, self.cache_table)
            return code
        end
        log_info("[CacheObj][save_impl] save:%s,%s,save_cnt:%s,update:%s", self.cache_name, self.primary_value, self.save_cnt, self.update_count)
        self.fail_cnt     = 0
        self.save_cnt     = self.save_cnt + 1
        self.update_count = 0
        self.update_time  = hive.clock_ms
        self.active_tick  = hive.clock_ms
        self.dirty        = false
        return code
    end
    return SUCCESS
end

function CacheObj:update(tab_data, flush)
    self:active()
    self.update_count = self.update_count + 1
    if flush or self.data == nil or not next(self.data) then
        self.flush = true
    end
    self.data  = tab_data
    self.dirty = true
    if flush then
        self.flush = true
    end
    return SUCCESS
end

function CacheObj:update_key(table_kvs, flush)
    if not self.data then
        log_err("[CacheObj][update_key] cannot find record! cache:%s, table:%s", self.cache_name, self.cache_table)
        return CacheCode.CACHE_KEY_IS_NOT_EXIST
    end
    self:active()
    self.update_count = self.update_count + 1
    if flush or not next(self.data) then
        self.flush = true
    end
    for key, value in pairs(table_kvs) do
        self.data[key] = value
    end
    self.dirty = true
    return SUCCESS
end

return CacheObj
