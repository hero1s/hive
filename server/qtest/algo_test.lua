local algo       = require("lalgo")
local log_info   = logger.info

local thread_mgr = hive.get("thread_mgr")

thread_mgr:fork(function()
    thread_mgr:sleep(1000)
    for i = 1, 100 do
        if algo.is_prime(i) then
            log_info("the %s is prime", i)
        end
    end


end)