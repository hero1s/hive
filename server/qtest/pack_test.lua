-- pack_test.lua
local tinsert    = table.insert
local tconcat    = table.concat
local log_info   = logger.info
local sname2sid  = service.name2sid

local router_mgr = hive.get("router_mgr")

local PackTest   = singleton()
function PackTest:__init()
    monitor:watch_service_ready(self, "proxy")
end

function PackTest:on_service_ready(hive_id)
    local service_id = sname2sid("proxy")
    local router     = router_mgr:hash_router(service_id)
    if router then
        local strs, args = {}, {}
        for i = 1, 1000 do
            tinsert(strs, "arg2....................")
        end
        local ss = tconcat(strs)
        for i = 1, 100000 do
            tinsert(args, ss)
        end
        local _, send_len = router.socket.call_target(hive_id, "test_log", 0, "arg_1", args, "arg_3")
        log_info("[PackTest][on_service_ready] send size : {}", send_len)
    end
end

-- export
hive.pack_test = PackTest()

return PackTest
