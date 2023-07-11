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
        { gm_type = GMType.DEV_OPS, name = "gm_build_db_index", desc = "构建db索引", comment = "", args = "" },
    }
    gm_agent:insert_command(cmd_list, self)
end

-- 构建db索引
function DBIndexMgr:gm_build_db_index()
    self:build_index()
    rmsg_agent:build_index()
    return { code = 0 }
end

function DBIndexMgr:build_index()
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
            if self.rebuild then
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
    if self.auto_build then
        thread_mgr:sleep(5000)
        self:build_index()
        rmsg_agent:build_index()
    end
end

hive.db_index_mgr = DBIndexMgr()

return DBIndexMgr
