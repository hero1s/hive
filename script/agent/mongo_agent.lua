--mongo_agent.lua
local mrandom       = math.random
local tunpack       = table.unpack

local router_mgr    = hive.get("router_mgr")

local MongoAgent = singleton()
function MongoAgent:__init()
end

--db_query: {coll_name, selector, fields}
function MongoAgent:find_one(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_find_one", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, fields, sortor, limit}
function MongoAgent:find(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_find", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, single}
function MongoAgent:delete(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_delete", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:update(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_update", db_name or "default", tunpack(db_query))
end

function MongoAgent:find_and_modify(db_query,hash_key,db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_find_and_modify", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj}
function MongoAgent:insert(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_insert", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector}
function MongoAgent:count(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_count", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, indexes}
function MongoAgent:create_indexes(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_create_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, index_name}
function MongoAgent:drop_indexes(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_drop_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {cmd, ...}
function MongoAgent:execute(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or mrandom(10000), "mongo_execute", db_name or "default", tunpack(db_query))
end
------------------------------------------------------------------
hive.mongo_agent = MongoAgent()

return MongoAgent
