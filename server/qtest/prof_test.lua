--log_test.lua
local lprof   = require("lprof")
local ProfObj = import("kernel/object/prof_obj.lua")

function test_a()
    local _prof<close> = ProfObj("test_a")
end

function test_b()
    local _prof<close> = ProfObj("test_b")
end

test_a()
test_b()

local info = lprof.shutdown()
logger.warn("prof:\n %s", info)




