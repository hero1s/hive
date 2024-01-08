import("kernel.lua")

hive.startup(function()
    import("store/mongo_mgr.lua")
    import("store/mysql_mgr.lua")
    import("store/redis_mgr.lua")
end)
