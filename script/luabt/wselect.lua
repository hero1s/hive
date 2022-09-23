--weight_select.lua
local ipairs    = ipairs
local tsort     = table.sort

local SUCCESS   = luabt.SUCCESS
local WAITING   = luabt.WAITING

local Node      = luabt.Node

local WSelectNode = class(Node)
function WSelectNode:__init(...)
    local childs = {...}
    tsort(childs, function(a, b)
        return a.weight < b.weight
    end)
    self.name = "weight_select"
    self.childs = childs
    self.index = 0
end

function WSelectNode:run(tree)
    local status = tree:get_status()
    if status == SUCCESS then
        return SUCCESS
    end
    local index = self.index + 1
    if index > #self.childs then
        return status
    end
    self.childs[index]:open(tree)
    self.index = index
    return WAITING
end

function WSelectNode:on_close(tree)
    self.index = 0
    for _, child in ipairs(self.childs) do
        child:close(tree)
    end
end

return WSelectNode
