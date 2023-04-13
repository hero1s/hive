local ReliableMsg   = import("store/reliable_msg.lua")

--dbtool_mgr.lua
--[[
    数据库运维服务,创建索引,导入数据等
]]
local tunpack       = table.unpack
local log_info      = logger.info
local log_err       = logger.err
local check_success = hive.success

local update_mgr    = hive.get("update_mgr")
local mongo_agent   = hive.get("mongo_agent")

local DbtoolMgr     = singleton()
local prop          = property(DbtoolMgr)
prop:reader("sync_status", true)
function DbtoolMgr:__init()

    update_mgr:attach_minute(self)

    mongo_agent:start_local_run()
end

function DbtoolMgr:on_minute()

end

function DbtoolMgr:build_mongo_index(dbindex_conf)
    for db_name, config in pairs(dbindex_conf) do
        for _, cfg in pairs(config or {}) do
            local query    = { cfg.table_name, cfg.indexes }
            local ok, code = mongo_agent:create_indexes(query, 1, db_name)
            if check_success(code, ok) then
                log_info("[DbtoolMgr][build_mongo_index] db[%s],table[%s] build index success", db_name, cfg.table_name)
            else
                log_err("DbtoolMgr][build_mongo_index db[%s],table[%s] build index[%s] faild:%s", db_name, cfg.table_name, cfg.indexes, code)
            end
        end
    end
end

function DbtoolMgr:build_rmsg_index(db_name, msg_table)
    local rmsgs = {}
    for k, v in pairs(msg_table) do
        rmsgs[k] = ReliableMsg(db_name, tunpack(v))
    end
    for _, rmsg in pairs(rmsgs) do
        rmsg:build_index()
    end
end


-- export
hive.dbtool_mgr = DbtoolMgr()

return DbtoolMgr


