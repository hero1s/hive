-- cache_row.lua
-- cache单行
local log_err      = logger.err
local log_debug    = logger.debug
local check_failed = hive.failed

local KernCode     = enum("KernCode")
local CacheCode    = enum("CacheCode")
local SUCCESS      = KernCode.SUCCESS

local mongo_mgr    = hive.get("mongo_mgr")

local CacheRow     = class()
local prop         = property(CacheRow)
prop:accessor("cache_table", nil)       -- cache table
prop:accessor("cache_key", "")          -- cache key
prop:accessor("primary_value", nil)     -- primary value
prop:accessor("db_name", "default")     -- database name
prop:accessor("dirty", false)           -- dirty
prop:accessor("save_cnt", 0)            -- 存储次数
prop:accessor("data", {})               -- data

--构造函数
function CacheRow:__init(row_conf, primary_value)
    self.primary_value = primary_value
    self.cache_table   = row_conf.cache_table
    self.cache_key     = row_conf.cache_key
end

--从数据库加载
function CacheRow:load(db_name)
    self.db_name    = db_name
    local query     = { [self.cache_key] = self.primary_value }
    local code, res = mongo_mgr:find_one(self.db_name, self.cache_table, query, { _id = 0 })
    if check_failed(code) then
        log_err("[CacheRow][load] failed: %s=> db: %s, table: %s", res, self.db_name, self.cache_table)
        return code
    end
    self.data = res
    return code
end

--保存数据库
function CacheRow:save()
    if self.dirty then
        local selector  = { [self.cache_key] = self.primary_value }
        local code, res = mongo_mgr:update(self.db_name, self.cache_table, self.data, selector, true)
        if check_failed(code) then
            log_err("[CacheRow][save] failed: %s=> db: %s, table: %s", res, self.db_name, self.cache_table)
            return code
        end
        self.save_cnt = self.save_cnt + 1
        self.dirty    = false
        log_debug("[CacheRow][save] %s:%s,save_cnt:%s", self.cache_table, self.primary_value, self.save_cnt)
        return code
    end
    return SUCCESS
end

--更新数据
function CacheRow:update(data, flush)
    self.data  = data
    self.dirty = true
    if flush or self.save_cnt == 0 then
        local code = self:save()
        if check_failed(code) then
            log_err("[CacheRow][update] flush failed: db: %s, table: %s", self.db_name, self.cache_table)
            return CacheCode.CACHE_FLUSH_FAILED
        end
    end
    return SUCCESS
end

--更新子数据
function CacheRow:update_key(table_kvs, flush)
    for key, value in pairs(table_kvs) do
        self.data[key] = value
    end
    self.dirty = true
    if flush then
        local code = self:save()
        if check_failed(code) then
            log_err("[CacheRow][update_key] flush failed: db: %s, table: %s", self.db_name, self.cache_table)
            return CacheCode.CACHE_FLUSH_FAILED
        end
    end
    return SUCCESS
end

return CacheRow
