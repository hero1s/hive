-- cache_mgr.lua
import("store/mongo_mgr.lua")
local WheelMap     = import("container/wheel_map.lua")

local log_err      = logger.err
local log_info     = logger.info
local tunpack      = table.unpack
local check_failed = hive.failed

local KernCode     = enum("KernCode")
local CacheCode    = enum("CacheCode")
local PeriodTime   = enum("PeriodTime")
local CacheType    = enum("CacheType")

local SUCCESS      = KernCode.SUCCESS
local CAREAD       = CacheType.READ
local CAWRITE      = CacheType.WRITE

local event_mgr    = hive.get("event_mgr")
local timer_mgr    = hive.get("timer_mgr")
local config_mgr   = hive.get("config_mgr")

local obj_table    = config_mgr:init_table("cache_obj", "cache_table")
local row_table    = config_mgr:init_table("cache_row", "cache_table")

local CacheMgr     = singleton()
local prop         = property(CacheMgr)
prop:reader("cache_enable", true)     -- 缓存开关
prop:reader("cache_confs", {})        -- cache_confs
prop:reader("cache_lists", {})        -- cache_lists
prop:reader("dirty_map", nil)         -- dirty objects
prop:reader("flush", false)            -- 立即存盘

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
    event_mgr:add_trigger(self, "evt_stop_service")
    --定时器
    timer_mgr:loop(PeriodTime.SECOND_MS, function(ms)
        self:on_timer_update(ms)
    end)
    timer_mgr:loop(PeriodTime.SECOND_10_MS, function(ms)
        self:on_timer_expire(ms)
    end)
end

function CacheMgr:setup()
    --加载配置
    for _, obj_conf in obj_table:iterator() do
        obj_conf.rows                = {}
        local cache_name             = obj_conf.cache_name
        self.cache_confs[cache_name] = obj_conf
        self.cache_lists[cache_name] = {}
    end
    for _, row_conf in row_table:iterator() do
        local cache_name = row_conf.cache_name
        local obj_conf   = self.cache_confs[cache_name]
        if obj_conf then
            local rows      = obj_conf.rows
            rows[#rows + 1] = row_conf
        else
            log_err("[CacheMgr:setup] cache row config obj:%s not exist !", cache_name)
        end
    end
    -- 创建WheelMap
    self.dirty_map = WheelMap(10)
end

function CacheMgr:evt_stop_service()
    log_err("[CacheMgr][evt_stop_service] enter flush mode,wait stop service:%s", hive.index)
    self.flush = true
end

function CacheMgr:on_timer_update()
    --存储脏数据
    if self.flush then
        for uuid, obj in self.dirty_map:iterator() do
            if obj:save() then
                self.dirty_map:set(uuid, nil)
            end
        end
        return
    end
    local now_tick = hive.clock_ms
    for uuid, obj in self.dirty_map:wheel_iterator() do
        if obj:check_store(now_tick) then
            self.dirty_map:set(uuid, nil)
        end
    end
end

function CacheMgr:on_timer_expire()
    --清理超时的记录
    local now_tick = hive.clock_ms
    for cache_name, obj_list in pairs(self.cache_lists) do
        for primary_key, obj in pairs(obj_list) do
            if obj:expired(now_tick) then
                log_info("[CacheMgr][on_timer_expire] cache(%s)'s data(%s) expired!", cache_name, primary_key)
                obj_list[primary_key] = nil
            end
        end
    end
end

--缓存加载
function CacheMgr:load_cache_impl(cache_list, conf, primary_key)
    local CacheObj          = import("cache/cache_obj.lua")
    local cache_obj         = CacheObj(conf, primary_key)
    cache_list[primary_key] = cache_obj
    local code              = cache_obj:load()
    if check_failed(code) then
        cache_list[primary_key] = nil
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
    local cache_obj = cache_list[primary_key]
    if cache_obj then
        if cache_obj:is_holding() then
            log_err("[CacheMgr][get_cache_obj] cache is holding! cache_name=%s,primary=%s", cache_name, primary_key)
            return CacheCode.CACHE_IS_HOLDING
        end
        if cache_type & CAWRITE == CAWRITE then
            local lock_node_id = cache_obj:get_lock_node_id()
            if lock_node_id == 0 then
                log_info("[CacheMgr][get_cache_obj] set lock node id:%s, cache_name=%s,primary=%s,cache_type=:%s", hive_id, cache_name, primary_key, cache_type)
                cache_obj:set_lock_node_id(hive_id)
            else
                if hive_id ~= lock_node_id then
                    log_err("[CacheMgr][get_cache_obj] cache node not match! %s != %s, cache_name=%s,primary=%s", hive_id, lock_node_id, cache_name, primary_key)
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
            log_info("[CacheMgr][get_cache_obj] init set lock node id:%s, cache_name=%s,primary=%s,cache_type=:%s", hive_id, cache_name, primary_key, cache_type)
            cobj:set_lock_node_id(hive_id)
        end
        return SUCCESS, cobj
    end
    log_err("[CacheMgr][get_cache_obj] cache object not exist! cache_name=%s,primary=%s,cache_type=%s", cache_name, primary_key, cache_type)
    return CacheCode.CACHE_IS_NOT_EXIST
end

function CacheMgr:rpc_cache_load(hive_id, req_data)
    local cache_name, primary_key, cache_type = tunpack(req_data)
    local code, cache_obj                     = self:get_cache_obj(hive_id, cache_name, primary_key, cache_type or CacheType.READ)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_load] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    log_info("[CacheMgr][rpc_cache_load] hive_id=%s,cache=%s,primary=%s,cache_type=%s", hive_id, cache_name, primary_key, cache_type)
    return SUCCESS, cache_obj:pack()
end

--更新缓存
function CacheMgr:rpc_cache_update(hive_id, req_data)
    local cache_name, primary_key, table_name, table_data, flush = tunpack(req_data)
    local code, cache_obj                                        = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.WRITE)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update(table_name, table_data, self.flush or flush)
    if cache_obj:is_dirty() then
        self.dirty_map:set(cache_obj:get_uuid(), cache_obj)
    end
    return ucode
end

--更新缓存kv
function CacheMgr:rpc_cache_update_key(hive_id, req_data)
    local cache_name, primary_key, table_name, table_kvs, flush = tunpack(req_data)
    local code, cache_obj                                       = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.WRITE)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_update_key] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    local ucode = cache_obj:update_key(table_name, table_kvs, self.flush or flush)
    if cache_obj:is_dirty() then
        self.dirty_map:set(cache_obj:get_uuid(), cache_obj)
    end
    return ucode
end

--删除缓存，通常由运维指令执行
function CacheMgr:rpc_cache_delete(hive_id, req_data)
    local cache_name, primary_key = tunpack(req_data)
    local code, cache_obj         = self:get_cache_obj(hive_id, cache_name, primary_key, CacheType.WRITE)
    if SUCCESS ~= code then
        log_err("[CacheMgr][rpc_cache_delete] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    if cache_obj:save() then
        self.cache_lists[cache_name][primary_key] = nil
        self.dirty_map:set(cache_obj:get_uuid(), nil)
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
        log_err("[CacheMgr][rpc_cache_flush] cache obj not find! cache_name=%s,primary=%s", cache_name, primary_key)
        return code
    end
    if cache_obj:save() then
        cache_obj:set_flush(true)
        cache_obj:set_lock_node_id(0)
        self.dirty_map:set(cache_obj:get_uuid(), nil)
        log_info("[CacheMgr][rpc_cache_flush] cache=%s,primary=%s", cache_name, primary_key)
        return SUCCESS
    end
    log_err("[CacheMgr][rpc_cache_flush] save failed: cache=%s,primary=%s", cache_name, primary_key)
    return CacheCode.CACHE_DELETE_SAVE_FAILD
end

hive.cache_mgr = CacheMgr()

return CacheMgr
