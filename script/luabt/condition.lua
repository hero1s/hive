--condition.lua

local Node      = luabt.Node
local WAITING   = luabt.WAITING

local ConditionNode = class(Node)
function ConditionNode:__init(success, failed)
    self.name = "condition"
    self.failed = failed
    self.success = success
    self.current = nil
end

function ConditionNode:run(tree)
    if not self.current  then
        if self:on_check(tree) then
            self.current = self.success
        else
            self.current = self.failed
        end
        self.current:open(tree)
        return WAITING
    end
    return tree.status
end

function ConditionNode:on_close(tree)
    self.success:close(tree)
    self.failed:close(tree)
    self.current = nil
end

function ConditionNode:on_check(tree)
    return true
end

return ConditionNode
