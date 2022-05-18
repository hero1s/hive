#!./hive
import("kernel.lua")

hive.startup(function()
    --初始化admin
    import("admin/admin_mgr.lua")
end)
