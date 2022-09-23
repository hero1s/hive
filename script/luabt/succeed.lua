--succeed.lua
local SUCCESS   = luabt.SUCCESS
local RUNNING   = luabt.RUNNING

local Node      = luabt.Node

local SucceedNode = class(Node)
function SucceedNode:__init()
    self.name = "always_succeed"
end

function SucceedNode:run(tree)
    local status = self:on_execute(tree)
    if status ~= RUNNING then
        return SUCCESS
    end
    return RUNNING
end

function SucceedNode:on_execute(tree)
    return SUCCESS
end

return SucceedNode
