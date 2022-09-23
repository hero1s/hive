--select.lua
local ipairs    = ipairs

local SUCCESS   = luabt.SUCCESS
local WAITING   = luabt.WAITING

local Node      = luabt.Node

local SelectNode = class(Node)
function SelectNode:__init(...)
    self.name = "select"
    self.childs = {...}
    self.index = 0
end

function SelectNode:run(tree)
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

function SelectNode:on_close(tree)
    self.index = 0
    for _, child in ipairs(self.childs) do
        child:close(tree)
    end
end

return SelectNode
