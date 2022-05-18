#!./hive
import("kernel.lua")

hive.startup(function()
    --初始化cachesvr
    import("cache/cache_mgr.lua")
end)

