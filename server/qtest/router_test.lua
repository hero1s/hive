-- route_test.lua
local log_info   = logger.info

local router_mgr = hive.get("router_mgr")

local RouterTest = singleton()
function RouterTest:__init()
end

function RouterTest:start()
    while true do
        -- 构造一个超过4096的字符串
        local msg = ""
        for n = 0, 5000 do
            msg = msg .. "6"
        end
        local ok, res = router_mgr:call_target(917505, "rpc_log_feishu", msg)
        log_info("RouterTest:start: ok=%s,res=%s", ok, res)
    end
end

-- export
hive.route_test = RouterTest()

return RouterTest
