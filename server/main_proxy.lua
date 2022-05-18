--proxy.lua
import("kernel.lua")

hive.startup(function()
    --初始化proxy
    import("proxy/proxy_mgr.lua")
end)
