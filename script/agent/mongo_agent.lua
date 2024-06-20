--mongo_agent.lua
local tunpack       = table.unpack
local check_failed  = hive.failed
local log_err       = logger.err
local log_info      = logger.info
local log_warn      = logger.warn
local mrandom       = math_ext.random
local tequals       = table_ext.equals
local tequal_keys   = table_ext.equal_keys
local KernCode      = enum("KernCode")
local router_mgr    = hive.load("router_mgr")
local scheduler     = hive.load("scheduler")
local check_success = hive.success

local AUTOINCCC     = environ.get("HIVE_DB_AUTOINCTB", "autoinctb")
local MongoAgent    = singleton()
local prop          = property(MongoAgent)
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
    return self:execute("rpc_mongo_find_one", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, fields, sortor, limit, skip}
function MongoAgent:find(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_find", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, single}
function MongoAgent:delete(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_delete", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector, single}
function MongoAgent:unsafe_delete(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_unsafe_delete", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:update(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_update", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj, selector, upsert, multi}
function MongoAgent:unsafe_update(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_unsafe_update", db_query, hash_key, db_name)
end

function MongoAgent:find_and_modify(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_find_and_modify", db_query, hash_key, db_name)
end

--db_query:{coll_name,pipeline,options}
function MongoAgent:aggregate(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_aggregate", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj}
function MongoAgent:insert(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_insert", db_query, hash_key, db_name)
end

--db_query: {coll_name, obj}
function MongoAgent:unsafe_insert(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_unsafe_insert", db_query, hash_key, db_name)
end

--db_query: {coll_name, selector}
function MongoAgent:count(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_count", db_query, hash_key, db_name)
end

function MongoAgent:get_indexes(coll_name, db_name)
    return self:execute("rpc_mongo_get_indexes", { coll_name }, coll_name, db_name)
end

--db_query: {coll_name, indexes}
function MongoAgent:create_indexes(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_create_indexes", db_query, hash_key, db_name)
end

--db_query: {coll_name, index_name}
function MongoAgent:drop_indexes(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_drop_indexes", db_query, hash_key, db_name)
end

--db_query: {cmd, ...}
function MongoAgent:run_command(db_query, hash_key, db_name)
    return self:execute("rpc_mongo_execute", db_query, hash_key, db_name)
end

function MongoAgent:execute(rpc, db_query, hash_key, db_name)
    hash_key = hash_key or mrandom()
    if self.local_run then
        return scheduler:call(self.service, rpc, db_name or "default", hash_key, tunpack(db_query))
    end
    if router_mgr then
        return router_mgr:call_dbsvr_hash(hash_key, rpc, db_name or "default", hash_key, tunpack(db_query))
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

--fields = { a=1,b=1}
function MongoAgent:remove_sheet_fields(sheet_name, primary_id, primary_key, fields, db_name)
    local udata         = { ["$unset"] = fields }
    local ok, code, res = self:update({ sheet_name, udata, { [primary_key] = primary_id }, true }, primary_id, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][remove_sheet_field] {} remove ({}) failed primary_id({}), code: {}, res: {}!", sheet_name, fields, primary_id, code, res)
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
function MongoAgent:check_indexes(index, co_name, db_name, only_key)
    local ok, code, indexs = self:get_indexes(co_name, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][check_indexes] failed:{},{},ok:{},code:{},indexs:{}", co_name, db_name, ok, code, indexs)
        return false
    end
    local cmp_func = only_key and tequal_keys or tequals
    for i, v in ipairs(indexs) do
        if cmp_func(v.key, index.key) then
            if index.unique and not v.unique then
                log_warn("[MongoAgent][check_indexes] db:{},table:{},index:{} --> {},is not unique", db_name, co_name, index, v)
                return false
            end
            if index.expireAfterSeconds and v.expireAfterSeconds ~= index.expireAfterSeconds then
                log_warn("[MongoAgent][check_indexes] db:{},table:{},index:{} --> {},expireAfterSeconds is not equal", db_name, co_name, index, v)
                return false
            end
            return true
        end
    end
    log_warn("[MongoAgent][check_indexes] db:{},table:{},index:{},is not exist indexes:{}", db_name, co_name, index, indexs)
    return false
end

--不存在则插入
function MongoAgent:insert_no_exist(doc, selector, co_name, db_name)
    local query            = { co_name, { ["$setOnInsert"] = doc }, selector, true }
    local ok, code, result = self:update(query, co_name, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][insert_no_exist] insert error ec={},result:{}, doc:{},selector:{}", code, result, doc, selector)
        return false, code
    end
    if result.upserted then
        return true, KernCode.SUCCESS
    end
    return false, KernCode.DATA_EXIST
end

--插入数组数据
function MongoAgent:push_array_data(selector, co_name, array, data, limit, hash_key, db_name)
    local query            = { co_name, { ["$push"] = { [array] = { ["$each"] = { data }, ["$slice"] = limit } } }, selector, true }
    local ok, code, result = self:update(query, hash_key, db_name)
    if check_failed(code, ok) then
        log_err("[MongoAgent][push_array_data] query:{} ec={},result:{}", query, code, result)
        return false
    end
    return true
end

--重建索引
function MongoAgent:rebuild_create_index(index, table_name, db_name, rebuild)
    --检测是否创建过索引
    if self:check_indexes(index, table_name, db_name, false) then
        log_info("[MongoAgent][rebuild_create_index] db[{}],table[{}],key[{}] is exist index", db_name, table_name, index.name)
        return true
    end
    local query    = { table_name, { index } }
    local ok, code = self:create_indexes(query, 1, db_name)
    if check_success(code, ok) then
        log_info("[MongoAgent][rebuild_create_index] db[{}],table[{}],key[{}] build index success", db_name, table_name, index.name)
        return true
    else
        log_err("[MongoAgent][rebuild_create_index] db[{}],table[{}] build index[{}] fail:{}", db_name, table_name, index, code)
        if rebuild then
            ok, code = self:drop_indexes({ table_name, index.name }, 1, db_name)
            if check_success(code, ok) then
                log_warn("[MongoAgent][rebuild_create_index] db[{}],table[{}],key[{}] drop index success", db_name, table_name, index.name)
                ok, code = self:create_indexes(query, 1, db_name)
                if check_success(code, ok) then
                    log_info("[MongoAgent][rebuild_create_index] db[{}],table[{}],key[{}] drop and build index success", db_name, table_name, index.name)
                    return true
                else
                    log_err("[MongoAgent][rebuild_create_index] db[{}],table[{}] drop and build index[{}] fail:{}", db_name, table_name, index, code)
                end
            else
                log_err("[MongoAgent][rebuild_create_index] db[{}],table[{}],key[{}] drop index fail:{}", db_name, table_name, index.name, code)
            end
        end
    end
    return false
end

hive.mongo_agent = MongoAgent()

return MongoAgent
