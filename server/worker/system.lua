import("driver/worker.lua")

--启动worker
hive.startup(function()
    import("worker/system/system_mgr.lua")
end)