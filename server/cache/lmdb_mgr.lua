local LMDB      = import("driver/lmdb.lua")
local log_debug = logger.debug
local sformat   = string.format

local LmdbMgr   = singleton()
local prop      = property(LmdbMgr)
prop:reader("open_status", false)
prop:reader("db", nil)

function LmdbMgr:__init()
    self:setup()
end

function LmdbMgr:setup()
    self.open_status = environ.status("HIVE_LMDB_OPEN")
    if self.open_status then
        local db_name = sformat("cache_db_%s", hive.index)
        self.db       = LMDB()
        self.db:open(db_name)
    end
end

function LmdbMgr:save_cache(cache_name, primary_key, data)
    if not self.open_status then
        return
    end
    log_debug("[LmdbMgr][save_cache] {},{}", cache_name, primary_key)
    self.db:put(primary_key, data, cache_name)
end

function LmdbMgr:load_cache(cache_name, primary_key)
    if not self.open_status then
        return nil, false
    end
    log_debug("[LmdbMgr][load_cache] {},{}", cache_name, primary_key)
    return self.db:get(primary_key, cache_name)
end

function LmdbMgr:delete_cache(cache_name, primary_key)
    if not self.open_status then
        return
    end
    log_debug("[LmdbMgr][delete_cache] {},{}", cache_name, primary_key)
    self.db:del(primary_key, cache_name)
end

function LmdbMgr:recover(cache_name, cache_mgr)
    if not self.open_status then
        return
    end
    log_debug("[LmdbMgr][recover] {}", cache_name)
    for key, value in self.db:iter(cache_name) do
        cache_mgr:recover_cacheobj(cache_name, key, value)
    end
end

hive.lmdb_mgr = LmdbMgr()

return LmdbMgr
