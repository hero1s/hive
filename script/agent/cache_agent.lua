-- cache_agent.lua

local log_err          = logger.err
local check_failed     = hive.failed
local check_success    = hive.success

local router_mgr       = hive.get("router_mgr")
local thread_mgr       = hive.get("thread_mgr")

local RPC_CALL_TIMEOUT = hive.enum("NetwkTime", "RPC_CALL_TIMEOUT")
local RPC_FAILED       = hive.enum("KernCode", "RPC_FAILED")
local CACHE_BOTH       = hive.enum("CacheType", "BOTH")
local CACHE_READ       = hive.enum("CacheType", "READ")

local CacheAgent       = singleton()
function CacheAgent:__init()
end

-- 加载
function CacheAgent:load(primary_key, cache_name, read_only)
    local cache_type         = read_only and CACHE_READ or CACHE_BOTH
    local req_data           = { cache_name, primary_key, cache_type }
    local ok, code, row_data = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_load", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][load] code=%s,res:%s,pkey=%s,cache=%s", code, row_data, primary_key, cache_name)
        return ok and code or RPC_FAILED
    end
    return code, row_data
end

-- 修改
function CacheAgent:update(primary_key, table_data, cache_name, flush)
    local req_data = { cache_name, primary_key, table_data, flush }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_update", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][update] faild: code=%s cache_name=%s,primary_key=%s", code, cache_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- 修改kv
function CacheAgent:update_key(primary_key, table_kvs, cache_name, flush)
    local req_data = { cache_name, primary_key, table_kvs, flush }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_update_key", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][update_key] faild: code=%s,cache_name=%s,primary_key=%s", code, cache_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- 删除
function CacheAgent:delete(primary_key, cache_name, sync)
    local req_data = { cache_name, primary_key }
    if sync then
        local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_delete", hive.id, req_data)
        if check_failed(code, ok) then
            log_err("[CacheAgent][delete] faild: code=%s,cache_name=%s,primary_key=%s", code, cache_name, primary_key)
            return ok and code or RPC_FAILED
        end
        return code
    else
        router_mgr:send_cachesvr_hash(primary_key, "rpc_cache_delete", hive.id, req_data)
    end
end

-- flush
function CacheAgent:flush(primary_key, cache_name, sync)
    local req_data = { cache_name, primary_key }
    if sync then
        local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_flush", hive.id, req_data)
        if check_failed(code, ok) then
            log_err("[CacheAgent][flush] faild: code=%s,cache_name=%s,primary_key=%s", code, cache_name, primary_key)
            return ok and code or RPC_FAILED
        end
        return code
    else
        router_mgr:send_cachesvr_hash(primary_key, "rpc_cache_flush", hive.id, req_data)
    end
end

-- 拉取集合
function CacheAgent:load_collect_by_cname(primary_key, cache_names, read_only)
    local tab_cnt    = 0
    local ret        = true
    local adata      = {}
    local session_id = thread_mgr:build_session_id()
    for _, cache_name in ipairs(cache_names or {}) do
        tab_cnt = tab_cnt + 1
        thread_mgr:fork(function()
            local code, data = self:load(primary_key, cache_name, read_only)
            if check_success(code) then
                adata[cache_name] = data
            else
                thread_mgr:response(session_id, false)
                return
            end
            thread_mgr:response(session_id, true)
        end)
    end
    while tab_cnt > 0 do
        local ok = thread_mgr:yield(session_id, "load_collect_name", RPC_CALL_TIMEOUT)
        if not ok then
            ret = false
        end
        tab_cnt = tab_cnt - 1
    end
    if not ret then
        if not read_only then
            for _, cache_name in ipairs(cache_names) do
                self:flush(primary_key, cache_name)
            end
        end
        return false
    end
    return true, adata
end

-- 拉取集合
function CacheAgent:load_collect_by_key(primary_keys, cache_name, read_only)
    local tab_cnt    = 0
    local ret        = true
    local adata      = {}
    local session_id = thread_mgr:build_session_id()
    for _, primary_key in ipairs(primary_keys or {}) do
        tab_cnt = tab_cnt + 1
        thread_mgr:fork(function()
            local code, data = self:load(primary_key, cache_name, read_only)
            if check_success(code) then
                adata[primary_key] = data
            else
                thread_mgr:response(session_id, false)
                return
            end
            thread_mgr:response(session_id, true)
        end)
    end
    while tab_cnt > 0 do
        local ok = thread_mgr:yield(session_id, "load_collect_key", RPC_CALL_TIMEOUT)
        if not ok then
            ret = false
        end
        tab_cnt = tab_cnt - 1
    end
    if not ret then
        if not read_only then
            for _, primary_key in ipairs(primary_keys) do
                self:flush(primary_key, cache_name)
            end
        end
        return false
    end
    return true, adata
end

-- export
hive.cache_agent = CacheAgent()

return CacheAgent
