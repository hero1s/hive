--dbtool.lua
import("kernel.lua")

hive.startup(function()
    --初始化dbtool
    import("dbtool/dbtool_mgr.lua")
end)