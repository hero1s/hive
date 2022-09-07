import("kernel.lua")

hive.startup(function()
    --初始化monitor
    import("monitor/monitor_mgr.lua")
    import("monitor/devops_gm.lua")
end)

