--redis_agent.lua
local tunpack    = table.unpack

local router_mgr = hive.get("router_mgr")

local RedisAgent = singleton()
function RedisAgent:__init()
end

--发送数据库请求
--db_query: { cmd, ...}
function RedisAgent:execute(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "redis_execute", db_name or "default", tunpack(db_query))
end

------------------------------------------------------------------
hive.redis_agent = RedisAgent()

return RedisAgent
