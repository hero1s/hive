--random.lua
local ipairs    = ipairs
local mrandom   = math.random

local WAITING   = luabt.WAITING

local Node      = luabt.Node

local RandomNode = class(Node)
function RandomNode:__init(...)
    self.name = "random"
    self.childs = {...}
    self.current = nil
end

function RandomNode:run(tree)
    if not self.current then
        local index = mrandom(#self.childs)
        local node = self.childs[index]
        self.current = node
        node:open(tree)
        return WAITING
    end
    return tree.status
end

function RandomNode:on_close(tree)
    self.current = nil
    for _, child in ipairs(self.childs) do
        child:close(tree)
    end
end

return RandomNode
