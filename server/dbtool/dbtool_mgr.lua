--dbtool_mgr.lua
--[[
    数据库运维服务,创建索引,导入数据等
]]

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

-- export
hive.dbtool_mgr = DbtoolMgr()

return DbtoolMgr


