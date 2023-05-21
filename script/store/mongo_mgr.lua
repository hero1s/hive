--mongo_mgr.lua
local sformat      = string.format
local KernCode     = enum("KernCode")
local SUCCESS      = KernCode.SUCCESS
local MONGO_FAILED = KernCode.MONGO_FAILED
local log_err      = logger.err
local tpack        = table.pack
local mrandom      = math.random
local event_mgr    = hive.get("event_mgr")
local config_mgr   = hive.get("config_mgr")

local MongoMgr     = singleton()
local prop         = property(MongoMgr)
prop:accessor("mongo_dbs", {})      -- mongo_dbs
prop:accessor("default_db", nil)    -- default_db
prop:accessor("db_count", 1)

function MongoMgr:__init()
    self.db_count = environ.number("HIVE_DB_POOL_COUNT", 5)
    self:setup()
    -- 注册事件
    event_mgr:add_listener(self, "mongo_find", "find")
    event_mgr:add_listener(self, "mongo_count", "count")
    event_mgr:add_listener(self, "mongo_insert", "insert")
    event_mgr:add_listener(self, "mongo_delete", "delete")
    event_mgr:add_listener(self, "mongo_update", "update")
    event_mgr:add_listener(self, "mongo_find_and_modify", "find_and_modify")
    event_mgr:add_listener(self, "mongo_execute", "execute")
    event_mgr:add_listener(self, "mongo_find_one", "find_one")
    event_mgr:add_listener(self, "mongo_drop_indexes", "drop_indexes")
    event_mgr:add_listener(self, "mongo_create_indexes", "create_indexes")
end

--初始化
function MongoMgr:setup()
    local MongoDB  = import("driver/mongo.lua")
    local database = config_mgr:init_table("database", "name")
    for _, conf in database:iterator() do
        local drivers = environ.driver(conf.url)
        if drivers and #drivers > 0 then
            local dconf = drivers[1]
            if dconf.driver == "mongodb" then
                local dbs = {}
                for i = 1, self.db_count do
                    local mongo_db = MongoDB(dconf, conf.max_ops or 5000)
                    table.insert(dbs, mongo_db)
                end
                self.mongo_dbs[conf.name] = dbs
                if conf.default then
                    self.default_db = dbs
                end
            end
        end
    end
end

--查找mongo db
function MongoMgr:get_db(db_name)
    if not db_name or db_name == "default" then
        return self.default_db[mrandom(self.db_count)]
    end
    return self.mongo_dbs[db_name][mrandom(self.db_count)]
end

function MongoMgr:find(db_name, coll_name, selector, fields, sortor, limit, skip)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:find(coll_name, selector, fields, sortor, limit, skip)
        if not ok then
            log_err("[MongoMgr][find] execute %s failed, because: %s", tpack(coll_name, selector, fields, sortor, limit, skip), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, "mongo db not exist"
end

function MongoMgr:find_one(db_name, coll_name, selector, fields)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:find_one(coll_name, selector, fields)
        if not ok then
            log_err("[MongoMgr][find_one] execute %s failed, because: %s", tpack(coll_name, selector, fields), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:insert(db_name, coll_name, obj)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:insert(coll_name, obj)
        if not ok then
            log_err("[MongoMgr][insert] execute %s failed, because: %s", tpack(coll_name, obj), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:update(db_name, coll_name, obj, selector, upsert, multi)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:update(coll_name, obj, selector, upsert, multi)
        if not ok then
            log_err("[MongoMgr][update] execute %s failed, because: %s", tpack(coll_name, obj, selector, upsert, multi), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:find_and_modify(db_name, coll_name, obj, selector, upsert, fields, new)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:find_and_modify(coll_name, obj, selector, upsert, fields, new)
        if not ok then
            log_err("[MongoMgr][find_and_modify] execute %s failed, because: %s", tpack(coll_name, obj, selector, upsert, fields, new), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:delete(db_name, coll_name, selector, onlyone)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:delete(coll_name, selector, onlyone)
        if not ok then
            log_err("[MongoMgr][delete] execute %s failed, because: %s", tpack(coll_name, selector, onlyone), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:count(db_name, coll_name, selector, limit, skip)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:count(coll_name, selector, limit, skip)
        if not ok then
            log_err("[MongoMgr][count] execute %s failed, because: %s", tpack(coll_name, selector, limit, skip), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:create_indexes(db_name, coll_name, indexes)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:create_indexes(coll_name, indexes)
        if not ok then
            log_err("[MongoMgr][create_indexes] execute %s failed, because: %s", tpack(coll_name, indexes), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:drop_indexes(db_name, coll_name, index_name)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:drop_indexes(coll_name, index_name)
        if not ok then
            log_err("[MongoMgr][drop_indexes] execute %s failed, because: %s", tpack(coll_name, index_name), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

function MongoMgr:execute(db_name, cmd, ...)
    local mongodb = self:get_db(db_name)
    if mongodb then
        local ok, res_oe = mongodb:runCommand(cmd, ...)
        if not ok then
            log_err("[MongoMgr][execute] execute %s failed, because: %s", tpack(cmd, ...), res_oe)
        end
        return ok and SUCCESS or MONGO_FAILED, res_oe
    end
    return MONGO_FAILED, sformat("mongo db:%s not exist", db_name)
end

hive.mongo_mgr = MongoMgr()

return MongoMgr
