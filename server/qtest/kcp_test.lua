-- kcp_test.lua
local lkcp = require("lkcp")

local log_debug     = logger.debug

local thread_mgr    = hive.get("thread_mgr")

if hive.index == 1 then
    local udp = lkcp.udp()
    local sessions = {}
    --kcp output
    local kcp_output = function(buff, session_id)
        local session = sessions[session_id]
        if session then
            udp:send(buff, #buff, session.ip, session.port)
        end
    end
    local find_kcp = function(ip, port)
        for session_id, session in pairs(sessions) do
            if session.ip == ip and session.port == port then
                return session.kcp
            end
        end
        local session_id = 1111
        local kcp = lkcp.kcp(session_id, kcp_output)
        sessions[session_id] = { kcp = kcp, ip = ip, port = port }
        return kcp
    end
    local ok, err = udp:listen("127.0.0.1", 8600)
    log_debug("kcp-svr listen: %s-%s", ok, err)
    thread_mgr:fork(function()
        local index = 0
        while true do
            local ok2, buf, ip, port = udp:recv()
            if ok2 then
                --input
                local kcp = find_kcp(ip, port)
                kcp:input(buf)
            else
                if buf ~= "EWOULDBLOCK" then
                    log_debug("kcp-svr recv failed: %s", buf)
                end
            end
            for session_id, session in pairs(sessions) do
                local kcp = session.kcp
                --update
                kcp:update(hive.now_ms)
                --recv
                local len, rbuf = kcp:recv()
                if len > 0 then
                    log_debug("kcp-svr recv: %s(len: %s) from %s", rbuf, len, session_id)
                    --send
                    index = index + 1
                    local buff = string.format("server send %s", index)
                    kcp:send(buff)
                end
            end
            --sleep
            thread_mgr:sleep(1000)
        end
    end)
elseif hive.index == 2 then
    local udp = lkcp.udp()
    --kcp output
    local kcp_output = function(buff)
        udp:send(buff, #buff, "127.0.0.1", 8600)
    end
    local session_id = 1111
    local kcp = lkcp.kcp(session_id, kcp_output)
    thread_mgr:fork(function()
        local index = 0
        local cdata = "kcp send 0!"
        kcp:send(cdata)
        while true do
            local ok, buf = udp:recv()
            if ok then
                kcp:input(buf)
            else
                if buf ~= "EWOULDBLOCK" then
                    log_debug("kcp-cli recv failed: %s", buf)
                end
            end
            --update
            kcp:update(hive.now_ms)
            --recv
            local len, rbuf = kcp:recv()
            if len > 0 then
                log_debug("kcp-cli recv: %s(len: %s) from %s", rbuf, len, session_id)
                --send
                index = index + 1
                local buff = string.format("client send %s", index)
                kcp:send(buff)
            end
            --sleep
            thread_mgr:sleep(1000)
        end
    end)
end
