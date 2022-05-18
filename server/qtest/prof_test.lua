--log_test.lua
local lprof        = require("lprof")

local prof_manager = lprof.new()

prof_manager.init()

prof_manager.start("root")
prof_manager.start("a")
prof_manager.start("b")
prof_manager.stop("b")
prof_manager.stop("a")
prof_manager.start("c")
prof_manager.stop("c")
prof_manager.stop("root")

local info = prof_manager.shutdown()
logger.warn("prof:\n %s", info)




