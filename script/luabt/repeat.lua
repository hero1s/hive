--repeat.lua

local RUNNING   = luabt.RUNNING

local Node      = luabt.Node

local RepeatNode = class(Node)
function RepeatNode:__init(node, count)
    self.name = "repeat"
    self.child = node
    self.count = count
    self.index = 0
end

function RepeatNode:run(tree)
    if self:on_check(tree) then
        self.child:open(tree)
        return RUNNING
    end
    self.index = self.index + 1
    return tree.status
end

function RepeatNode:on_close()
    self.index = 0
end

function RepeatNode:on_check(tree)
    return self.index < self.count
end

return RepeatNode
