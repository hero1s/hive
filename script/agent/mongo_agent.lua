--mongo_agent.lua
local tunpack      = table.unpack
local check_failed = hive.failed
local log_err      = logger.err
local log_info     = logger.info

local router_mgr   = hive.get("router_mgr")

local MongoAgent   = singleton()
function MongoAgent:__init()
end

--db_query: {coll_name, selector, fields}
function MongoAgent:find_one(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_find_one", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, fields, sortor, limit, skip}
function MongoAgent:find(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_find", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector, single}
function MongoAgent:delete(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_delete", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:update(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_update", db_name or "default", tunpack(db_query))
end

function MongoAgent:find_and_modify(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_find_and_modify", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, obj}
function MongoAgent:insert(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_insert", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, selector}
function MongoAgent:count(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_count", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, indexes}
function MongoAgent:create_indexes(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_create_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {coll_name, index_name}
function MongoAgent:drop_indexes(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_drop_indexes", db_name or "default", tunpack(db_query))
end

--db_query: {cmd, ...}
function MongoAgent:execute(db_query, hash_key, db_name)
    return router_mgr:call_dbsvr_hash(hash_key or hive.id, "mongo_execute", db_name or "default", tunpack(db_query))
end
------------------------------------------------------------------

--获取自增id
function MongoAgent:get_inc_id(id_name, tb_name, db_name, inc_value)
    local ok, code, res = self:find_and_modify({ tb_name, { ["$inc"] = { [id_name] = inc_value or 1 } }, {}, true, { _id = 0 } }, nil, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][get_inc_id] create %s failed! code: %s, res: %s", id_name, code, res)
        return 0
    end
    local id = res.value[id_name]
    log_info("[MongoAgent][get_inc_id] db_inc_id new %s:%s", id_name, id)
    return id
end

hive.mongo_agent = MongoAgent()

return MongoAgent
