-- tcp_test.lua
local luabus        = require("luabus")

local log_debug     = logger.debug

local thread_mgr    = hive.get("thread_mgr")

if hive.index == 1 then
    local tcp = luabus.tcp()
    local ok, err = tcp.listen("127.0.0.1", 8700)
    log_debug("tcp-svr listen: %s, err: %s", ok, err)
    thread_mgr:fork(function()
        local index = 0
        local client = nil
        while true do
            if not client then
                local socket = tcp.accept(500)
                if socket then
                    client = socket
                    log_debug("tcp-svr accept success!")
                end
            else
                local ok2, buf = client.recv()
                if ok2 then
                    index = index + 1
                    log_debug("tcp-svr recv: %s", buf)
                    local buff = string.format("server send %s", index)
                    client.send(buff)
                else
                    if buf ~= "timeout" then
                        log_debug("tcp-svr failed: %s", buf)
                        client = nil
                    end
                end
            end
        end
    end)
elseif hive.index == 2 then
    thread_mgr:fork(function()
        local index = 0
        local client = nil
        while true do
            if not client then
                local socket = luabus.tcp()
                local ok, err = socket.connect("127.0.0.1", 8700, 500)
                if ok then
                    client = socket
                    local cdata = "client send 0!"
                    client.send(cdata, #cdata)
                    log_debug("tcp-cli connect success!")
                else
                    log_debug("tcp-cli connect failed: %s!", err)
                end
            else
                local ok, buf = client.recv()
                if ok then
                    index = index + 1
                    log_debug("tcp-cli recv: %s", buf)
                    local buff = string.format("client send %s", index)
                    client.send(buff)
                else
                    if buf ~= "timeout" then
                        log_debug("tcp-cli failed: %s", buf)
                        client = nil
                    end
                end
            end
        end
    end)
end
