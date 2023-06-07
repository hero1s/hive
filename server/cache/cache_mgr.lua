-- cache_mgr.lua
import("store/mongo_mgr.lua")
local CacheObj     = import("cache/cache_obj.lua")
local log_err      = logger.err
local log_info     = logger.info
local tunpack      = table.unpack
local check_failed = hive.failed
local sid2nick     = service.id2nick

local KernCode     = enum("KernCode")
local CacheCode    = enum("CacheCode")
local CacheType    = enum("CacheType")

local SUCCESS      = KernCode.SUCCESS
local CAREAD       = CacheType.READ
local CAWRITE      = CacheType.WRITE

local thread_mgr   = hive.get("thread_mgr")
local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")
local update_mgr   = hive.get("update_mgr")
local monitor      = hive.get("monitor")

local obj_table    = config_mgr:init_table("dbcache", "cache_name")

local CacheMgr     = singleton()
local prop         = property(CacheMgr)
prop:reader("cache_confs", {})        -- cache_confs
prop:reader("cache_lists", {})        -- cache_lists
prop:reader("dirty_maps", {})          -- dirty objects
prop:reader("flush", false)           -- 立即存盘

function CacheMgr:__init()
    --初始化cache
    self:setup()
    -- 监听rpc事件
    event_mgr:add_listener(self, "rpc_cache_load")
    event_mgr:add_listener(self, "rpc_cache_update")
    event_mgr:add_listener(self, "rpc_cache_update_key")
    event_mgr:add_listener(self, "rpc_cache_delete")
    event_mgr:add_listener(self, "rpc_cache_flush")
    -- 订阅停服事件
    event_mgr:add_trigger(self, "evt_change_service_status")
    event_mgr:add_vote(self, "vote_stop_service")
    --定时器
    update_mgr:attach_second(self)
    update_mgr:attach_second5(self)

    monitor:watch_service_close(self, "*")
    monitor:watch_service_ready(self, "*")
end

function CacheMgr:setup()
    local WheelMap = import("container/wheel_map.lua")
    --加载配置
    for _, obj_conf in obj_table:iterator() do
        local cache_name             = obj_conf.cache_name
        self.cache_confs[cache_name] = obj_conf
        self.cache_lists[cache_name] = WheelMap(10)
        self.dirty_maps[cache_name]  = WheelMap(10)
    end
end

function CacheMgr:vote_stop_service()
    for _, dirty_map in pairs(self.dirty_maps) do
        if dirty_map:get_count() > 0 then
            return false
        end
    end
    return true
end

function CacheMgr:evt_change_service_status(status)
    if not hive.is_runing() then
        log_info("[CacheMgr][evt_change_service_status] enter flush mode,wait stop service:%s", hive.index)
        self.flush = true
        for _, dirty_map in pairs(self.dirty_maps) do
            for _, obj in dirty_map:iterator() do
                self:save_cache(obj)
            end
        end
        return
    end
    self.flush = false
end

function CacheMgr:on_service_close(id, service_name)
    log_info("[CacheMgr][on_service_close] disconnect:%s", sid2nick(id))
    for cache_name, obj_list in pairs(self.cache_lists) do
        for primary_key, obj in obj_list:iterator() do
            if obj:get_lock_node_id() == id then
                log_info("[CacheMgr][on_service_close] %s unlock by service close!", primary_key)
                obj:set_lock_node_id(0)
                self:save_cache(obj, true)
            end
        end
    end
end

function CacheMgr:on_service_ready(id, service_name)
    log_info("[CacheMgr][on_service_ready] connect:%s", sid2nick(id))
    for cache_name, obj_list in pairs(self.cache_lists) do
        for primary_key, obj in obj_list:iterator() do
            if obj:get_lock_node_id() == id then
                log_info("[CacheMgr][on_service_ready] %s unlock by service close!", primary_key)
                obj:set_lock_node_id(0)
                self:save_cache(obj, true)
            end
        end
    end
end

function CacheMgr:on_second(clock_ms)
    for _, dirty_map in pairs(self.dirty_maps) do
        for _, obj in dirty_map:wheel_iterator() do
            if self.flush or obj:need_save(clock_ms) then
                self:save_cache(obj)
            end
        end
    end
end

--清理超时的记录
function CacheMgr:on_second5(clock_ms)
    for cache_name, obj_list in pairs(self.cache_lists) do
        for primary_key, obj in obj_list:wheel_iterator() do
            if obj:expired(clock_ms, self.flush) then
                log_info("[CacheMgr][on_second5] cache(%s)'s data(%s) expired!", cache_name, primary_key)
                obj_list:set(primary_key, nil)
            end
        end
    end
end

--设置标记
function CacheMgr:set_dirty(cache_obj, is_dirty)
    local dirty_map = self.dirty_maps[cache_obj.cache_name]
    dirty_map:set(cache_obj:get_primary_value(), is_dirty and cache_obj or nil)
end

function CacheMgr:delete(cache_obj)
    local cache_name  = cache_obj:get_cache_name()
    local primary_key = cache_obj:get_primary_value()
    local cache_list  = self.cache_lists[cache_name]
    if not cache_list then
        log_err("[CacheMgr][delete] cache list not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return false
    end
    cache_list:set(primary_key, nil)
    log_info("[CacheMgr][delete] cache=%s,primary=%s", cache_name, primary_key)
end

function CacheMgr:save_cache(cache_obj, remove)
    thread_mgr:fork(function()
        self:set_dirty(cache_obj, false)
        if not cache_obj:save() then
            self:set_dirty(cache_obj, true)
        end
        if remove then
            cache_obj:set_expire_time(1)
        end
    end)
    return true
end

--缓存加载
function CacheMgr:load_cache_impl(cache_list, conf, primary_key)
    local cache_obj = CacheObj(conf, primary_key)
    cache_list:set(primary_key, cache_obj)
    local code = cache_obj:load()
    if check_failed(code) then
        cache_list:set(primary_key, nil)
        return code
    end
    return SUCCESS, cache_obj
end

function CacheMgr:get_cache_obj(hive_id, cache_name, primary_key, cache_type)
    local cache_list = self.cache_lists[cache_name]
    if not cache_list then
        log_err("[CacheMgr][get_cache_obj] cache list not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return CacheCode.CACHE_NOT_SUPPERT
    end
    local cache_obj = cache_list:get(primary_key)
    if cache_obj then
        if cache_obj:is_holding() then
            log_err("[CacheMgr][get_cache_obj] cache is holding! cache_name=%s,primary=%s,cache_type:%s", cache_name, primary_key, cache_type)
            return CacheCode.CACHE_IS_HOLDING
        end
        if cache_type & CAWRITE == CAWRITE then
            local lock_node_id = cache_obj:get_lock_node_id()
            if lock_node_id == 0 then
                log_info("[CacheMgr][get_cache_obj] set lock node id:%s, cache_name=%s,primary=%s,cache_type=:%s", sid2nick(hive_id), cache_name, primary_key, cache_type)
                cache_obj:set_lock_node_id(hive_id)
            else
                if hive_id ~= lock_node_id then
                    log_err("[CacheMgr][get_cache_obj] cache node not match! %s != %s, cache_name=%s,primary=%s", sid2nick(hive_id), sid2nick(lock_node_id), cache_name, primary_key)
                    return CacheCode.CACHE_KEY_LOCK_FAILD
                end
            end
        end
        cache_obj:active()
        return SUCCESS, cache_obj
    end
    if cache_type & CAREAD == CAREAD then
        local conf       = self.cache_confs[cache_name]
        local code, cobj = self:load_cache_impl(cache_list, conf, primary_key)
        if check_failed(code) then
            return code
        end
        if cache_type & CAWRITE == CAWRITE then
            log_info("[CacheMgr][get_cache_obj] init set lock node id:%s, cache_name=%s,primary=%s,cache_type=:%s", sid2nick(hive_id), cache_name, primary_key, cache_type)
            cobj:set_lock_node_id(hive_id)
        end
        return SUCCESS, cobj
    end
    if cache_type ~= CAWRITE then
        log_err("[CacheMgr][get_cache_obj] cache object not exist! cache_name=%s,primary=%s,cache_type=%s,from:%s", cache_name, primary_key, cache_type, hive.where_call())
    end
    return CacheCode.CACHE_IS_NOT_EXIST
end

function CacheMgr:rpc_cache_load(hive_id, req_data)
    local cache_name, primary_key, cache_type = tunpack(req_data)
    local code, cache_obj                     = self:get_cache_obj(hive_id, cache_name, primary_key, cache_type or CacheType.READ)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_load] cache obj not find! cache_name=%s,primary=%s,cache_type=%s", cache_name, primary_key, cache_type)
        return code
    end
    log_info("[CacheMgr][rpc_cache_load] from=%s,cache=%s,primary=%s,cache_type=%s", sid2nick(hive_id), cache_name, primary_key, cache_type)
    return SUCCESS, cache_obj:pack()
end

--更新缓存
function CacheMgr:rpc_cache_update(hive_id, req_data)
    local cache_name, primary_key, table_data, flush = tunpack(req_data)
    local code, cache_obj                            = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.BOTH)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update(table_data, flush)
    self:set_dirty(cache_obj, true)
    if cache_obj:need_save(hive.clock_ms) then
        self:save_cache(cache_obj)
    end
    return ucode
end

--更新缓存kv
function CacheMgr:rpc_cache_update_key(hive_id, req_data)
    local cache_name, primary_key, table_kvs, flush = tunpack(req_data)
    local code, cache_obj                           = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.BOTH)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update_key] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update_key(table_kvs, flush)
    self:set_dirty(cache_obj, true)
    if cache_obj:need_save(hive.clock_ms) then
        self:save_cache(cache_obj)
    end
    return ucode
end

--删除缓存，通常由运维指令执行
function CacheMgr:rpc_cache_delete(hive_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj         = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.WRITE)
    if SUCCESS ~= code then
        if code == CacheCode.CACHE_IS_NOT_EXIST then
            return SUCCESS
        end
        log_err("[CacheMgr][rpc_cache_delete] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    if self:save_cache(cache_obj, true) then
        log_info("[CacheMgr][rpc_cache_delete] cache=%s,primary=%s", cache_name, primary_key)
        return SUCCESS
    end
    log_err("[CacheMgr][rpc_cache_delete] save failed: cache=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_DELETE_SAVE_FAILD
end

--缓存落地
function CacheMgr:rpc_cache_flush(hive_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj         = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.WRITE)
    if SUCCESS ~= code then
        if code == CacheCode.CACHE_IS_NOT_EXIST then
            return SUCCESS
        end
        log_err("[CacheMgr][rpc_cache_flush] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    cache_obj:set_lock_node_id(0)
    if self:save_cache(cache_obj, true) then
        log_info("[CacheMgr][rpc_cache_flush] cache=%s,primary=%s", cache_name, primary_key)
        return SUCCESS
    end
    log_err("[CacheMgr][rpc_cache_flush] save failed: cache=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_DELETE_SAVE_FAILD
end

hive.cache_mgr = CacheMgr()

return CacheMgr
