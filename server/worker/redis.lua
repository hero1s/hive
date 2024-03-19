--启动worker
hive.startup(function()
    import("store/redis_mgr.lua")
end)