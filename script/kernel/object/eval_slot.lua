--eval_slot.lua
--[[性能上报
示例:
    local _<close> = perfeval_mgr:eval(key)
    ...
--]]

local EvalSlot = class()
local prop = property(EvalSlot)
prop:reader("host", nil)
prop:reader("eval_data", nil)

function EvalSlot:__init(host, key)
    self.host = host
    self.eval_data = host:start(key)
end

function EvalSlot:__defer()
    self.host:stop(self.eval_data)
end

return EvalSlot
