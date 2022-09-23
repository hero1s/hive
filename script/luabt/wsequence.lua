--weight_sequence.lua
local ipairs    = ipairs
local tsort     = table.sort

local FAIL      = luabt.FAIL
local WAITING   = luabt.WAITING

local Node      = luabt.Node

local WSequenceNode = class(Node)
function WSequenceNode:__init(...)
    local childs = {...}
    tsort(childs, function(a, b)
        return a.weight < b.weight
    end)
    self.name = "weight_sequence"
    self.childs = childs
    self.index = 0
end

function WSequenceNode:run(tree)
    local status = tree:get_status()
    if status == FAIL then
        return FAIL
    end
    local index = self.index + 1
    if index > #self.childs then
        return status
    end
    self.childs[index]:open(tree)
    self.index = index
    return WAITING
end

function WSequenceNode:on_close(tree)
    self.index = 0
    for _, child in ipairs(self.childs) do
        child:close(tree)
    end
end

return WSequenceNode
