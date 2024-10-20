--dbindex_mgr.lua
import("agent/rmsg_agent.lua")
local tinsert     = table.insert
local tjoin       = table_ext.join
local log_err     = logger.err
local log_info    = logger.info
local log_warn    = logger.warn

local monitor     = hive.get("monitor")
local mongo_agent = hive.get("mongo_agent")
local thread_mgr  = hive.get("thread_mgr")
local gm_agent    = hive.get("gm_agent")
local rmsg_agent  = hive.get("rmsg_agent")
local config_mgr  = hive.get("config_mgr")

local GMType      = enum("GMType")

local dbindex_db  = config_mgr:init_table("dbindex", "db_name", "table_name", "name")

local DBIndexMgr  = singleton()
local prop        = property(DBIndexMgr)
prop:accessor("status", 0)
prop:accessor("sharding", false)
prop:accessor("rebuild", false)
prop:accessor("auto_build", false)

function DBIndexMgr:__init()
    self.sharding   = environ.status("HIVE_MONGO_SHARDING")
    self.rebuild    = environ.status("HIVE_MONGO_INDEX_REBUILD")
    self.auto_build = environ.status("HIVE_AUTO_BUILD_MONGO_INDEX")

    monitor:watch_service_ready(self, "dbsvr")
    self:setup()
end

function DBIndexMgr:setup()
    self:register_gm()
end

function DBIndexMgr:register_gm()
    local cmd_list = {
        { group = "运维", gm_type = GMType.GLOBAL, name = "gm_check_db_index", desc = "检测db索引", comment = "检测db索引(1先构建)", args = "build|integer" },
    }
    gm_agent:insert_command(cmd_list, self)
end

-- 检测/构建db索引
function DBIndexMgr:gm_check_db_index(build)
    if build == 1 then
        self:build_index(self.rebuild)
    end
    local ok, res = self:check_dbindexes()
    if not ok then
        log_err("[DBIndexMgr][gm_check_db_index] not create dbindex:{},please fast repair !!!", res)
    end
    return { code = ok, res = res }
end

function DBIndexMgr:build_index(rebuild)
    log_info("[DBIndexMgr][build_index] rebuild:{}", rebuild)
    self:build_dbindex(rebuild)
    rmsg_agent:build_index(self.sharding, rebuild)
end

function DBIndexMgr:check_dbindexes()
    local success = true
    local miss    = {}
    for _, conf in dbindex_db:iterator() do
        local db_name    = conf.db_name
        local table_name = conf.table_name
        local only_key   = true
        if self.auto_build then
            only_key = false
        end
        --线上分片键只检测key
        if self.sharding and conf.sharding then
            only_key = true
        end
        local index = self:generate_index(conf)
        if not mongo_agent:check_indexes(index, table_name, db_name, only_key) then
            success = false
            tinsert(miss, { db = db_name, co = table_name, index = index })
        end
    end
    local ok, res = rmsg_agent:check_indexes(self.sharding)
    if not ok then
        miss    = tjoin(res, miss)
        success = false
    end
    log_warn("[DBIndexMgr][check_dbindexes] ret:{},miss:{}", success, miss)
    return success, miss
end

-- 检测表是否分片
function DBIndexMgr:get_key_unique(db_name, table_name, unique)
    if self.sharding then
        for _, conf in dbindex_db:iterator() do
            if db_name == conf.db_name and table_name == conf.table_name and conf.sharding then
                return false
            end
        end
    end
    return unique
end

function DBIndexMgr:generate_index(conf)
    local index      = {}
    index.key        = {}
    index.name       = conf.name
    index.unique     = self:get_key_unique(conf.db_name, conf.table_name, conf.unique)
    index.background = true
    if conf.expireAfterSeconds > 0 then
        index.expireAfterSeconds = conf.expireAfterSeconds
    end
    for k, v in ipairs(conf.keys) do
        local v_type = 1
        if conf.types and #conf.types >= k then
            v_type = conf.types[k]
        end
        index.key[v] = v_type
    end
    return index
end

function DBIndexMgr:build_dbindex(rebuild)
    log_info("[DBIndexMgr][build_dbindex] rebuild:{},sharding:{}", rebuild, self.sharding)
    for _, conf in dbindex_db:iterator() do
        if not self.sharding or not conf.sharding then
            local index = self:generate_index(conf)
            mongo_agent:rebuild_create_index(index, conf.table_name, conf.db_name, rebuild)
        end
    end
end

--db连接成功
function DBIndexMgr:on_service_ready(id, service_name)
    log_info("[DBIndexMgr][on_service_ready] {}", service.id2nick(id))
    if self.status > 0 then
        return
    end
    self.status = 1
    thread_mgr:sleep(15000)
    if self.auto_build then
        self:build_index(self.rebuild)
    end
    --启动检测索引
    thread_mgr:success_call(300000, function()
        local ok, res = self:check_dbindexes()
        if not ok then
            log_err("[DBIndexMgr][on_service_ready] not create dbindex:{},please fast repair !!!", res)
        end
        return ok
    end, 1000, 100000)
end

hive.db_index_mgr = DBIndexMgr()

return DBIndexMgr
