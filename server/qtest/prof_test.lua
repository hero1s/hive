--log_test.lua
local lprof        = require("lprof")

local new_prof   = hive.new_prof

function test_a()
    local _prof<close> = new_prof("test_a")
end

function test_b()
    local _prof<close> = new_prof("test_b")
end

test_a()
test_b()


--local prof_manager = lprof.new()
--
--prof_manager.init()
--
--prof_manager.start("root")
--prof_manager.start("a")
--prof_manager.start("b")
--prof_manager.stop("b")
--prof_manager.stop("a")
--prof_manager.start("c")
--prof_manager.stop("c")
--prof_manager.stop("root")
--
--local report = prof_manager.report()
--logger.warn("prof report:\n %s",report)
--
--local info = prof_manager.shutdown()
--logger.warn("prof:\n %s", info)




