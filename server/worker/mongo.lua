import("feature/worker.lua")

--启动worker
hive.startup(function()
    import("store/mongo_mgr.lua")
end)