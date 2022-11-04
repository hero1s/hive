-- cache_agent.lua

local log_err      = logger.err
local check_failed = hive.failed

local router_mgr   = hive.get("router_mgr")

local RPC_FAILED   = hive.enum("KernCode", "RPC_FAILED")
local CACHE_BOTH   = hive.enum("CacheType", "BOTH")

local CacheAgent   = singleton()
function CacheAgent:__init()
end

-- 加载
function CacheAgent:load(primary_key, cache_name, cache_type)
    local req_data           = { cache_name, primary_key, cache_type or CACHE_BOTH }
    local ok, code, row_data = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_load", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][load] code=%s,pkey=%s,cache=%s", code, primary_key, cache_name)
        return ok and code or RPC_FAILED
    end
    return code, row_data
end

-- 修改
function CacheAgent:update(primary_key, table_name, table_data, cache_name, flush)
    local req_data = { cache_name, primary_key, table_name, table_data, flush }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_update", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][update] faild: code=%s cache_name=%s,table_name=%s,primary_key=%s", code, cache_name, table_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- 修改kv
function CacheAgent:update_key(primary_key, table_name, table_kvs, cache_name, flush)
    local req_data = { cache_name, primary_key, table_name, table_kvs, flush }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_update_key", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][update_key] faild: code=%s,cache_name=%s,table_name=%s,primary_key=%s", code, cache_name, table_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- 删除
function CacheAgent:delete(primary_key, cache_name)
    local req_data = { cache_name, primary_key }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_delete", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][delete] faild: code=%s,cache_name=%s,primary_key=%s", code, cache_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- flush
function CacheAgent:flush(primary_key, cache_name)
    local req_data = { cache_name, primary_key }
    local ok, code = router_mgr:call_cachesvr_hash(primary_key, "rpc_cache_flush", hive.id, req_data)
    if check_failed(code, ok) then
        log_err("[CacheAgent][flush] faild: code=%s,cache_name=%s,primary_key=%s", code, cache_name, primary_key)
        return ok and code or RPC_FAILED
    end
    return code
end

-- export
hive.cache_agent = CacheAgent()

return CacheAgent
