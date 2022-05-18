--router.lua
import("kernel.lua")

hive.startup(function()
    --初始化router
    import("router/router_server.lua")
end)

