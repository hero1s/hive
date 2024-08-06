--mongo_mgr.lua
local sformat      = string.format
local KernCode     = enum("KernCode")
local SUCCESS      = KernCode.SUCCESS
local MONGO_FAILED = KernCode.MONGO_FAILED
local log_err      = logger.err
local tpack        = table.pack
local mrandom      = math_ext.random
local hdefer       = hive.defer

local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")

local MongoMgr     = singleton()
local prop         = property(MongoMgr)
prop:accessor("mongo_dbs", {})      -- mongo_dbs
prop:accessor("default_db", nil)    -- default_db
prop:reader("table_queues", {})
prop:reader("table_counters", {})
prop:reader("table_queue_size", 5)
prop:reader("table_queue_limit", 100)
prop:reader("qps_warn_avg", 1)

function MongoMgr:__init()
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "rpc_mongo_find", "find")
    event_mgr:add_listener(self, "rpc_mongo_count", "count")
    event_mgr:add_listener(self, "rpc_mongo_insert", "insert")
    event_mgr:add_listener(self, "rpc_mongo_unsafe_insert", "unsafe_insert")
    event_mgr:add_listener(self, "rpc_mongo_delete", "delete")
    event_mgr:add_listener(self, "rpc_mongo_unsafe_delete", "unsafe_delete")
    event_mgr:add_listener(self, "rpc_mongo_update", "update")
    event_mgr:add_listener(self, "rpc_mongo_unsafe_update", "unsafe_update")
    event_mgr:add_listener(self, "rpc_mongo_find_and_modify", "find_and_modify")
    event_mgr:add_listener(self, "rpc_mongo_execute", "execute")
    event_mgr:add_listener(self, "rpc_mongo_find_one", "find_one")
    event_mgr:add_listener(self, "rpc_mongo_drop_indexes", "drop_indexes")
    event_mgr:add_listener(self, "rpc_mongo_create_indexes", "create_indexes")
    event_mgr:add_listener(self, "rpc_mongo_get_indexes", "get_indexes")
    event_mgr:add_listener(self, "rpc_mongo_aggregate", "aggregate")
end

--初始化
function MongoMgr:setup()
    self.table_queue_size  = environ.number("HIVE_MONGO_TABLE_QUEUE", 50)
    self.table_queue_limit = environ.number("HIVE_MONGO_TABLE_QUEUE_LIMIT", 500)
    self.qps_warn_avg      = environ.number("HIVE_MONGO_TABLE_QPS", 120)

    local MongoDB          = import("driver/mongo_new.lua")
    local database         = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local dconf = environ.driver(conf.url)
        if dconf then
            if dconf.driver == "mongodb" then
                local mongo_db            = MongoDB(dconf)
                self.mongo_dbs[conf.name] = mongo_db
                if conf.default then
                    self.default_db = mongo_db
                end
            end
        end
    end
end

--查找mongo db
function MongoMgr:get_db(db_name, hash_key, coll_name)
    local mongodb
    if not db_name or db_name == "default" then
        mongodb = self.default_db
    else
        mongodb = self.mongo_dbs[db_name]
    end
    if mongodb and mongodb:set_executer(hash_key or mrandom()) then
        if coll_name then
            local queue = self:change_table_queue(coll_name, 1)
            if queue > self.table_queue_size then
                if queue > self.table_queue_limit then
                    log_err("[MongoMgr][get_db] table {} queue size {} > {} is too busy!!!,limit and refuse", coll_name, queue, self.table_queue_limit)
                    self:change_table_queue(coll_name, -1)
                    return nil
                end
                log_err("[MongoMgr][get_db] table {} queue size {} > {} is too busy!!!,check logic is right ?", coll_name, queue, self.table_queue_size)
            end
            self:count_qps(coll_name)
        end
        return mongodb
    end
    return nil
end

function MongoMgr:find(db_name, hash_key, coll_name, selector, fields, sortor, limit, skip)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:find(coll_name, selector, fields, sortor, limit, skip)
        if not ok then
            log_err("[MongoMgr][find] execute {} failed, because: {}", tpack(coll_name, selector, fields, sortor, limit, skip), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, "mongo db not exist"
end

function MongoMgr:find_one(db_name, hash_key, coll_name, selector, fields)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:find_one(coll_name, selector, fields)
        if not ok then
            log_err("[MongoMgr][find_one] execute {} failed, because: {}", tpack(coll_name, selector, fields), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:insert(db_name, hash_key, coll_name, obj)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:insert(coll_name, obj)
        if not ok then
            log_err("[MongoMgr][insert] execute {} failed, because: {}", tpack(coll_name, obj), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:unsafe_insert(db_name, hash_key, coll_name, obj)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:unsafe_insert(coll_name, obj)
        if not ok then
            log_err("[MongoMgr][unsafe_insert] execute {} failed, because: {}", tpack(coll_name, obj), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:update(db_name, hash_key, coll_name, obj, selector, upsert, multi)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:update(coll_name, obj, selector, upsert, multi)
        if not ok then
            log_err("[MongoMgr][update] execute {} failed, because: {}", tpack(coll_name, obj, selector, upsert, multi), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:unsafe_update(db_name, hash_key, coll_name, obj, selector, upsert, multi)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:unsafe_update(coll_name, obj, selector, upsert, multi)
        if not ok then
            log_err("[MongoMgr][unsafe_update] execute {} failed, because: {}", tpack(coll_name, obj, selector, upsert, multi), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:find_and_modify(db_name, hash_key, coll_name, obj, selector, upsert, fields, new)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:find_and_modify(coll_name, obj, selector, upsert, fields, new)
        if not ok then
            log_err("[MongoMgr][find_and_modify] execute {} failed, because: {}", tpack(coll_name, obj, selector, upsert, fields, new), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:delete(db_name, hash_key, coll_name, selector, onlyone)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:delete(coll_name, selector, onlyone)
        if not ok then
            log_err("[MongoMgr][delete] execute {} failed, because: {}", tpack(coll_name, selector, onlyone), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:unsafe_delete(db_name, hash_key, coll_name, selector, onlyone)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:unsafe_delete(coll_name, selector, onlyone)
        if not ok then
            log_err("[MongoMgr][unsafe_delete] execute {} failed, because: {}", tpack(coll_name, selector, onlyone), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:count(db_name, hash_key, coll_name, selector, limit, skip)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:count(coll_name, selector, limit, skip)
        if not ok then
            log_err("[MongoMgr][count] execute {} failed, because: {}", tpack(coll_name, selector, limit, skip), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:get_indexes(db_name, hash_key, coll_name)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:get_indexes(coll_name)
        if not ok then
            log_err("[MongoMgr][get_indexes] execute {} failed, because: {}", coll_name, res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:create_indexes(db_name, hash_key, coll_name, indexes)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:create_indexes(coll_name, indexes)
        if not ok then
            log_err("[MongoMgr][create_indexes] execute {} failed, because: {}", tpack(coll_name, indexes), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:drop_indexes(db_name, hash_key, coll_name, index_name)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:drop_indexes(coll_name, index_name)
        if not ok then
            log_err("[MongoMgr][drop_indexes] execute {} failed, because: {}", tpack(coll_name, index_name), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:aggregate(db_name, hash_key, coll_name, pipeline, options)
    local mongodb = self:get_db(db_name, hash_key, coll_name)
    if mongodb then
        local _<close>   = hdefer(function()
            self:change_table_queue(coll_name, -1)
        end)
        local ok, res_oe = mongodb:aggregate(coll_name, pipeline, options)
        if not ok then
            log_err("[MongoMgr][aggregate] execute {} failed, because: {}", tpack(coll_name, pipeline, options), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:execute(db_name, hash_key, cmd, ...)
    local mongodb = self:get_db(db_name, hash_key)
    if mongodb then
        local ok, res_oe = mongodb:runCommand(cmd, ...)
        if not ok then
            log_err("[MongoMgr][execute] execute {} failed, because: {}", tpack(cmd, ...), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:change_table_queue(table_name, value)
    local queue = self.table_queues[table_name]
    if not queue then
        self.table_queues[table_name] = value
    else
        self.table_queues[table_name] = queue + value
    end
    return self.table_queues[table_name]
end

function MongoMgr:count_qps(table_name)
    local qps_counter = self.table_counters[table_name]
    if not qps_counter then
        qps_counter                     = hive.make_sampling(sformat("mongo [%s] qps", table_name), nil, self.qps_warn_avg)
        self.table_counters[table_name] = qps_counter
    end
    qps_counter:count_increase()
end

hive.mongo_mgr = MongoMgr()

return MongoMgr
