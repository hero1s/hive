--mongo_agent.lua
local tunpack      = table.unpack
local check_failed = hive.failed
local log_err      = logger.err
local log_info     = logger.info
local log_warn     = logger.warn
local mrandom      = math_ext.random
local tequals      = table_ext.equals
local tequal_keys  = table_ext.equal_keys
local KernCode     = enum("KernCode")
local router_mgr   = hive.load("router_mgr")
local scheduler    = hive.load("scheduler")

local AUTOINCCC    = environ.get("HIVE_DB_AUTOINCTB", "autoinctb")
local MongoAgent   = singleton()
local prop         = property(MongoAgent)
prop:reader("service", "mongo")
prop:reader("local_run", false) --本地线程服务

function MongoAgent:__init()
end

function MongoAgent:start_local_run()
    if self.local_run then
        return
    end
    --启动代理线程
    self.local_run = scheduler:startup(self.service, "worker.mongo")
end

--db_query: {coll_name, selector, fields}
function MongoAgent:find_one(db_query, hash_key, db_name)
    return self:execute("mongo_find_one", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, fields, sortor, limit, skip}
function MongoAgent:find(db_query, hash_key, db_name)
    return self:execute("mongo_find", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, single}
function MongoAgent:delete(db_query, hash_key, db_name)
    return self:execute("mongo_delete", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, single}
function MongoAgent:unsafe_delete(db_query, hash_key, db_name)
    return self:execute("mongo_unsafe_delete", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:update(db_query, hash_key, db_name)
    return self:execute("mongo_update", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:unsafe_update(db_query, hash_key, db_name)
    return self:execute("mongo_unsafe_update", db_query, hash_key, db_name)
end

function MongoAgent:find_and_modify(db_query, hash_key, db_name)
    return self:execute("mongo_find_and_modify", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj}
function MongoAgent:insert(db_query, hash_key, db_name)
    return self:execute("mongo_insert", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj}
function MongoAgent:unsafe_insert(db_query, hash_key, db_name)
    return self:execute("mongo_unsafe_insert", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector}
function MongoAgent:count(db_query, hash_key, db_name)
    return self:execute("mongo_count", db_query, hash_key, db_name)
end

function MongoAgent:get_indexes(coll_name, db_name)
    return self:execute("mongo_get_indexes", { coll_name }, coll_name, db_name)
end

--db_query: {coll_name, indexes}
function MongoAgent:create_indexes(db_query, hash_key, db_name)
    return self:execute("mongo_create_indexes", db_query, hash_key, db_name)
end

--db_query: {coll_name, index_name}
function MongoAgent:drop_indexes(db_query, hash_key, db_name)
    return self:execute("mongo_drop_indexes", db_query, hash_key, db_name)
end

--db_query: {cmd, ...}
function MongoAgent:rum_command(db_query, hash_key, db_name)
    return self:execute("mongo_execute", db_query, hash_key, db_name)
end

function MongoAgent:execute(rpc, db_query, hash_key, db_name)
    if self.local_run then
        return scheduler:call(self.service, rpc, db_name or "default", tunpack(db_query))
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key or mrandom(), rpc, db_name or "default", tunpack(db_query))
    end
    return false, KernCode.FAILED, "init not right"
end

function MongoAgent:get_autoinc_id(id_key, inc_value, min_id, db_name)
    local query         = { key = id_key }
    local fields        = { autoinc_id = 1 }
    local update        = { ["$inc"] = { ["autoinc_id"] = inc_value or 1 } }
    local ok, code, res = self:find_and_modify({ AUTOINCCC, update, query, true, fields, true }, id_key, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][get_autoinc_id] create {} failed! code: {}, res: {}", id_key, code, res)
        return 0
    end
    local id = res.value.autoinc_id
    if min_id and id < min_id then
        return self:get_autoinc_id(id_key, min_id - id, nil, db_name)
    end
    log_info("[MongoAgent][get_autoinc_id] autoinc_id new {}:{}", id_key, id)
    return id
end

--------------KV数据快捷数据接口------------------------------------------
--加载mongo
function MongoAgent:load_sheet(sheet_name, primary_id, primary_key, filters, db_name)
    local ok, code, adata = self:find_one({ sheet_name, { [primary_key] = primary_id }, filters or { _id = 0 } }, primary_id, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][load_mongo_{}] primary_id: {} find failed! code: {}, res: {}", sheet_name, primary_id, code, adata)
        return false
    end
    return true, adata or {}
end

function MongoAgent:delete_sheet(sheet_name, primary_id, primary_key, db_name)
    local ok, code, res = self:delete({ sheet_name, { [primary_key] = primary_id }, true }, primary_id, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][delete_mongo_{}] delete failed primary_id({}), code: {}, res: {}!", sheet_name, primary_id, code, res)
        return false
    end
    return true
end

function MongoAgent:update_sheet_fields(sheet_name, primary_id, primary_key, field_datas, db_name)
    local udata         = { ["$set"] = field_datas }
    local ok, code, res = self:update({ sheet_name, udata, { [primary_key] = primary_id } }, primary_id, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][update_mongo_field_{}] update ({}) failed! primary_id({}), code({}), res({})", sheet_name, field_datas, primary_id, code, res)
        return false
    end
    return true
end

function MongoAgent:update_sheet(sheet_name, primary_id, primary_key, udata, db_name)
    local ok, code, res = self:update({ sheet_name, udata, { [primary_key] = primary_id }, true }, primary_id, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][update_mongo_{}] update ({}) failed! primary_id({}), code({}), res({})", sheet_name, udata, primary_id, code, res)
        return false
    end
    return true
end

--检测是否建立了索引(only_key仅检测字段名)
function MongoAgent:check_indexes(key, co_name, db_name, only_key)
    local ok, code, indexs = self:get_indexes(co_name, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][check_indexes] failed:{},{},ok:{},code:{},indexs:{}", co_name, db_name, ok, code, indexs)
        return false
    end
    local cmp_func = only_key and tequal_keys or tequals
    for i, v in ipairs(indexs) do
        if cmp_func(v.key, key) then
            return true
        end
    end
    log_warn("[MongoAgent][check_indexes] db:{},table:{},key:{},is not exist indexes:{}", db_name, co_name, key, indexs)
    return false
end

hive.mongo_agent = MongoAgent()

return MongoAgent
