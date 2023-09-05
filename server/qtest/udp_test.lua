-- udp_test.lua
local log_debug  = logger.debug

local thread_mgr = hive.get("thread_mgr")

if hive.index == 1 then
    local udp     = luabus.udp()
    local ok, err = udp.listen("127.0.0.1", 8600)
    log_debug("udp-svr listen: %s, err: %s", ok, err)
    thread_mgr:fork(function()
        local index = 0
        while true do
            local ok2, buf, ip, port = udp.recv()
            if ok2 then
                index = index + 1
                log_debug("udp-svr recv: %s from %s:%s", buf, ip, port)
                local buff = string.format("server send %s", index)
                udp.send(buff, #buff, ip, port)
            else
                if buf ~= "EWOULDBLOCK" then
                    log_debug("udp-svr recv failed: %s", buf)
                end
            end
            thread_mgr:sleep(1000)
        end
    end)
elseif hive.index == 2 then
    local udp = luabus.udp()
    thread_mgr:fork(function()
        local index = 0
        local cdata = "client send 0!"
        udp.send(cdata, #cdata, "127.0.0.1", 8600)
        log_debug("client send first msg")
        while true do
            local ok, buf, ip, port = udp.recv()
            if ok then
                index = index + 1
                log_debug("udp-cli recv: %s from %s:%s", buf, ip, port)
                local buff = string.format("client send %s", index)
                udp.send(buff, #buff, ip, port)
            else
                if buf ~= "EWOULDBLOCK" then
                    log_debug("udp-cli recv failed: %s", buf)
                end
            end
            thread_mgr:sleep(1000)
        end
    end)
end
