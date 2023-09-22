-- mongo_test.lua
local log_debug  = logger.debug

local event_mgr  = hive.get("event_mgr")
local thread_mgr = hive.get("thread_mgr")
local router_mgr = hive.get("router_mgr")

local RpcTest    = singleton()

function RpcTest:__init()
    self:setup()
end

function RpcTest:setup()
    event_mgr:add_listener(self, "on_echo")

    thread_mgr:fork(function()
        local data = {}
        for l = 1, 61 do
            for m = 1, 1024 do
                table.insert(data, 1 * m)
            end
        end
        thread_mgr:sleep(3000)
        for n = 1, 200 do
            local ok, rn, rdata = router_mgr:call_target(hive.id, "on_echo", n, data)
            if ok then
                log_debug("{} res: {}", rn, #rdata)
            else
                log_debug("{} err: {}", n, rn)
            end
        end
    end)
end

function RpcTest:on_echo(n, data)
    log_debug("{} req: {}", n, #data)
    return n, data
end

-- export
hive.rpc_test = RpcTest()

return RpcTest

