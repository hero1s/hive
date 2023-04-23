--dbindex_mgr.lua
import("agent/rmsg_agent.lua")

local log_err       = logger.err
local log_info      = logger.info
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

function DBIndexMgr:__init()
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
    local dbindex_db = config_mgr:init_table("dbindex", "id")
    for _, conf in dbindex_db:iterator() do
        local db_name    = conf.db_name
        local table_name = conf.table_name
        local index      = {}
        index.key        = {}
        index.name       = conf.name
        index.unique     = conf.unique
        if conf.expireAfterSeconds > 0 then
            index.expireAfterSeconds = conf.expireAfterSeconds
        end
        for _, v in ipairs(conf.keys) do
            table.insert(index.key, { [v] = 1 })
        end
        local query    = { table_name, { index } }
        local ok, code = mongo_agent:create_indexes(query, 1, db_name)
        if check_success(code, ok) then
            log_info("[DBIndexMgr][build_index] db[%s],table[%s],key[%s] build index success", db_name, table_name, index.name)
        else
            log_err("[DBIndexMgr][build_index] db[%s],table[%s] build index[%s] faild:%s", db_name, table_name, index, code)
        end
    end
end

--db连接成功
function DBIndexMgr:on_service_ready(id, service_name)
    if self.status > 0 then
        return
    end
    self.status = 1
    thread_mgr:sleep(5000)
    self:build_index()
    rmsg_agent:build_index()
end

hive.db_index_mgr = DBIndexMgr()

return DBIndexMgr
