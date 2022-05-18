-- ws_test.lua

local log_debug     = logger.debug

local data = { aaa = 123 }
local on_message = function(url, message)
    log_debug("on_message: %s, %s", url, message)
    return data
end
local WSServer = import("network/ws_server.lua")
local server = WSServer("0.0.0.0:8001")
server:register_handler("*", on_message)
hive.server = server
