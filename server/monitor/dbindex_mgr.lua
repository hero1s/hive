--dbindex_mgr.lua
import("agent/rmsg_agent.lua")
local tinsert       = table.insert
local log_err       = logger.err
local log_info      = logger.info
local log_warn      = logger.warn
local check_success = hive.success
local monitor       = hive.get("monitor")
local mongo_agent   = hive.get("mongo_agent")
local thread_mgr    = hive.get("thread_mgr")
local gm_agent      = hive.get("gm_agent")
local rmsg_agent    = hive.get("rmsg_agent")
local config_mgr    = hive.get("config_mgr")

local GMType        = enum("GMType")

local DBIndexMgr    = singleton()
local prop          = property(DBIndexMgr)
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
        { gm_type = GMType.DEV_OPS, name = "gm_check_db_index", desc = "检测db索引", comment = "检测db索引(1先构建)", args = "build|integer" },
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
        log_err("[DBIndexMgr][gm_check_db_index] not create dbindex:%s,please fast repair !!!", res)
    end
    return { code = ok, res = res }
end

function DBIndexMgr:build_index(rebuild)
    self:build_dbindex(rebuild)
    rmsg_agent:build_index(self.sharding)
end

function DBIndexMgr:check_dbindexes()
    local success    = true
    local miss       = {}
    local dbindex_db = config_mgr:init_table("dbindex", "db_name", "table_name", "name")
    for _, conf in dbindex_db:iterator() do
        local db_name    = conf.db_name
        local table_name = conf.table_name
        local only_key   = false
        --线上分片键只检测key
        if self.sharding and conf.sharding then
            only_key = true
        end
        local check_key = {}
        for _, v in ipairs(conf.keys) do
            check_key[v] = 1
        end
        if not mongo_agent:check_indexes(check_key, table_name, db_name, only_key) then
            success = false
            tinsert(miss, { db = db_name, co = table_name, key = check_key })
        end
    end
    return success, miss
end

function DBIndexMgr:build_dbindex(rebuild)
    local dbindex_db = config_mgr:init_table("dbindex", "db_name", "table_name", "name")
    for _, conf in dbindex_db:iterator() do
        if self.sharding and conf.sharding then
            goto continue
        end
        local db_name    = conf.db_name
        local table_name = conf.table_name
        local index      = {}
        index.key        = {}
        index.name       = conf.name
        index.unique     = conf.unique
        index.background = true
        if conf.expireAfterSeconds > 0 then
            index.expireAfterSeconds = conf.expireAfterSeconds
        end
        for _, v in ipairs(conf.keys) do
            tinsert(index.key, { [v] = 1 })
        end
        local query    = { table_name, { index } }
        local ok, code = mongo_agent:create_indexes(query, 1, db_name)
        if check_success(code, ok) then
            log_info("[DBIndexMgr][build_index] db[%s],table[%s],key[%s] build index success", db_name, table_name, index.name)
        else
            log_err("[DBIndexMgr][build_index] db[%s],table[%s] build index[%s] fail:%s", db_name, table_name, index, code)
            if rebuild then
                ok, code = mongo_agent:drop_indexes({ table_name, index.name }, 1, db_name)
                if check_success(code, ok) then
                    log_warn("[DBIndexMgr][build_index] db[%s],table[%s],key[%s] drop index success", db_name, table_name, index.name)
                    ok, code = mongo_agent:create_indexes(query, 1, db_name)
                    if check_success(code, ok) then
                        log_info("[DBIndexMgr][build_index] db[%s],table[%s],key[%s] drop and build index success", db_name, table_name, index.name)
                    else
                        log_err("[DBIndexMgr][build_index] db[%s],table[%s] drop and build index[%s] fail:%s", db_name, table_name, index, code)
                    end
                else
                    log_err("[DBIndexMgr][build_index] db[%s],table[%s],key[%s] drop index fail:%s", db_name, table_name, index.name, code)
                end
            end
        end
        :: continue ::
    end
end

--db连接成功
function DBIndexMgr:on_service_ready(id, service_name)
    if self.status > 0 then
        return
    end
    self.status = 1
    thread_mgr:sleep(15000)
    if self.auto_build then
        self:build_index(self.rebuild)
    end
    --启动检测索引
    local ok, res = self:check_dbindexes()
    if not ok then
        thread_mgr:success_call(2000, function()
            log_err("[DBIndexMgr][on_service_ready] not create dbindex:%s,please fast repair !!!", res)
            return false
        end)
    end
end

hive.db_index_mgr = DBIndexMgr()

return DBIndexMgr
