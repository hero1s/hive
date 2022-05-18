--dbsvr.lua
import("kernel.lua")

hive.startup(function()
    --初始化dbsvr
    import("store/mongo_mgr.lua")
    import("store/mysql_mgr.lua")
    import("store/redis_mgr.lua")
end)
