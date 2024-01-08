import("kernel.lua")

hive.startup(function()
    import("monitor/monitor_mgr.lua")
    import("monitor/devops_gm.lua")
    import("monitor/dbindex_mgr.lua")
end)

