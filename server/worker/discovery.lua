import("feature/worker.lua")

--启动worker
hive.startup(function()
    import("worker/discovery/nacos_mgr.lua")
end)