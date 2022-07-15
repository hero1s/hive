--prof_obj.lua
--[[性能打点对象
示例:
    local prof<close> = hive.new_prof(key)
    ...
--]]

local ProfObj = class()
local prop = property(ProfObj)

prop:reader("prof_mgr", nil)
prop:reader("key", nil)

function ProfObj:__init(prof_mgr, key)
    self.prof_mgr = prof_mgr
    self.key = key
    self.prof_mgr.start(self.key)
end

function ProfObj:__defer()
    self.prof_mgr.stop(self.key)
end

return ProfObj
