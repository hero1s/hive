--redis_agent.lua
local tunpack       = table.unpack
local mrandom       = math_ext.random
local check_success = hive.success
local log_err       = logger.err
local json_decode   = hive.json_decode
local json_encode   = hive.json_encode

local KernCode      = enum("KernCode")
local router_mgr    = hive.load("router_mgr")
local scheduler     = hive.load("scheduler")

local RedisAgent    = singleton()
local prop          = property(RedisAgent)
prop:reader("service", "redis")
prop:reader("local_run", false) --本地线程服务

function RedisAgent:__init()
end

function RedisAgent:redis_lock(lock_key, lock_time)
    local expire_time                  = hive.now + lock_time
    local lock_ok, lock_code, lock_res = self:execute({ "set", lock_key, expire_time, "ex", lock_time, "nx" })
    if check_success(lock_code, lock_ok) and lock_res == "OK" then
        return true
    end
    return false
end

function RedisAgent:set(key, value, etime)
    if type(value) == "table" then
        value = json_encode(value)
    end
    local ok, code, res = self:execute({ "set", key, value, "ex", etime or -1 }, key)
    if check_success(code, ok) then
        return true
    end
    log_err("[RedisAgent][set] ok:%s,code:%s,res:%s", ok, code, res)
    return false
end

function RedisAgent:get(key, is_table)
    local ok, code, res = self:execute({ "get", key }, key)
    if check_success(code, ok) then
        if is_table then
            local ok1, data = json_decode(res, true)
            if ok1 then
                return data
            end
        end
        return true, res
    end
    log_err("[RedisAgent][get] ok:%s,code:%s,res:%s", ok, code, res)
    return false
end

function RedisAgent:delete(key)
    local ok, code, res = self:execute({ "del", key }, key)
    if check_success(code, ok) then
        return true
    end
    log_err("[RedisAgent][delete] ok:%s,code:%s,res:%s", ok, code, res)
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
        return scheduler:call(self.service, "redis_execute", db_name or "default", hash_key, tunpack(db_query))
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key or mrandom(), "redis_execute", db_name or "default", hash_key, tunpack(db_query))
    end
    return false, KernCode.FAILED, "init not right"
end

------------------------------------------------------------------
hive.redis_agent = RedisAgent()

return RedisAgent
