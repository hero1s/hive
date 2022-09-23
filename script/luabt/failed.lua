--failed.lua
local FAIL      = luabt.FAIL
local RUNNING   = luabt.RUNNING

local Node      = luabt.Node

local FailedNode = class(Node)
function FailedNode:__init()
    self.name = "always_fail"
end

function FailedNode:run(tree)
    local status = self:on_execute(tree)
    if status ~= RUNNING then
        return FAIL
    end
    return status
end

function FailedNode:on_execute(tree)
    return FAIL
end

return FailedNode
