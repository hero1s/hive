--redis_agent.lua
local tunpack       = table.unpack
local mrandom       = math_ext.random
local check_success = hive.success
local log_err       = logger.err

local KernCode      = enum("KernCode")
local router_mgr    = hive.load("router_mgr")
local scheduler     = hive.load("scheduler")

local RedisAgent    = singleton()
local prop          = property(RedisAgent)
prop:reader("service", "redis")
prop:reader("local_run", false) --本地线程服务

function RedisAgent:__init()
end

function RedisAgent:try_lock(key, seconds)
    local expire_time   = hive.now + seconds
    local ok, code, res = self:execute({ "set", key, expire_time, "ex", seconds, "nx" })
    if check_success(code, ok) and res == "OK" then
        return true
    end
    return false
end

function RedisAgent:set(key, value, etime)
    local ok, code, res = self:execute({ "set", key, value, "ex", etime or 0xFFFFFFFF }, key)
    if check_success(code, ok) then
        return true
    end
    log_err("[RedisAgent][set] ok:{},code:{},res:{},ref:{}", ok, code, res, hive.where_call())
    return false
end

function RedisAgent:get(key)
    local ok, code, res = self:execute({ "get", key }, key)
    if check_success(code, ok) then
        return true, res
    end
    log_err("[RedisAgent][get] ok:{},code:{},res:{},ref:{}", ok, code, res, hive.where_call())
    return false
end

function RedisAgent:delete(key)
    local ok, code, res = self:execute({ "del", key }, key)
    if check_success(code, ok) then
        return true
    end
    log_err("[RedisAgent][delete] ok:{},code:{},res:{},ref:{}", ok, code, res, hive.where_call())
    return false
end

function RedisAgent:expire(key, seconds)
    local ok, code, res = self:execute({ "expire", key, seconds }, key)
    if check_success(code, ok) then
        return true
    end
    log_err("[RedisAgent][expire] ok:{},code:{},res:{},ref:{}", ok, code, res, hive.where_call())
    return false
end

function RedisAgent:autoinc_id(key)
    local ok, code, res = self:execute({ "incr", key }, key)
    if check_success(code, ok) then
        return true, res
    end
    log_err("[RedisAgent][autoinc_id] ok:{},code:{},res:{},ref:{}", ok, code, res, hive.where_call())
    return false
end

function RedisAgent:start_local_run()
    if self.local_run then
        return
    end
    --启动代理线程
    self.local_run = scheduler:startup(self.service, "worker.redis")
end

--发送数据库请求
--db_query: { cmd, ...}
function RedisAgent:execute(db_query, hash_key, db_name)
    if self.local_run then
        return scheduler:call(self.service, "rpc_redis_execute", db_name or "default", tunpack(db_query))
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key or mrandom(), "rpc_redis_execute", db_name or "default", tunpack(db_query))
    end
    return false, KernCode.FAILED, "init not right"
end

------------------------------------------------------------------
hive.redis_agent = RedisAgent()

return RedisAgent
