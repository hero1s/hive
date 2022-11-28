--prof_obj.lua
--性能打点对象
local lprof   = require("lprof")

local ProfObj = class()
local prop    = property(ProfObj)

prop:reader("key", nil)

function ProfObj:__init(key)
    self.key      = key
    lprof.start(self.key)
end

function ProfObj:__defer()
    lprof.stop(self.key)
end

return ProfObj
