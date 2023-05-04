--redis_agent.lua
local tunpack    = table.unpack

local KernCode   = enum("KernCode")
local router_mgr = hive.load("router_mgr")
local scheduler  = hive.load("scheduler")

local RedisAgent = singleton()
local prop       = property(RedisAgent)
prop:reader("service", "redis")
prop:reader("local_run", false) --本地线程服务

function RedisAgent:__init()
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
        return scheduler:call(nil, self.service, "redis_execute", db_name or "default", tunpack(db_query))
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key or hive.id, "redis_execute", db_name or "default", tunpack(db_query))
    end
    return false, KernCode.FAILED, "init not right"
end

------------------------------------------------------------------
hive.redis_agent = RedisAgent()

return RedisAgent
