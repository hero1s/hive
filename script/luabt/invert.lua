--invert.lua

local FAIL      = luabt.FAIL
local SUCCESS   = luabt.SUCCESS

local Node      = luabt.Node

local InvertNode = class(Node)
function InvertNode:__init()
    self.name = "invert"
end

function InvertNode:run(tree)
    local status = self:on_execute(tree)
    if status == SUCCESS then
        return FAIL
    end
    if status == FAIL then
        return SUCCESS
    end
    return status
end

function InvertNode:on_execute(tree)
    return SUCCESS
end

return InvertNode
