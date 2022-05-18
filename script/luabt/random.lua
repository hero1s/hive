--random.lua
local ipairs       = ipairs
local mrandom      = math.random

local FAIL         = luabt.BTConst.FAIL
local SUCCESS      = luabt.BTConst.SUCCESS

local node_execute = luabt.node_execute

local RandomNode   = class()
function RandomNode:__init(...)
    self.name     = "random"
    self.children = { ... }
end

function RandomNode:open(_, node_data)
    node_data.runningChild = mrandom(#self.children)
end

function RandomNode:run(btree, node_data)
    local child  = node_data.runningChild
    local node   = self.children[child]
    local status = node_execute(node, btree, node_data.__level + 1)
    if status == SUCCESS then
        return status
    end
    return FAIL
end

function RandomNode:close(btree)
    for _, node in ipairs(self.children) do
        local child_data = btree[node]
        if child_data and child_data.is_open then
            child_data.is_open = false
            if node.close then
                node:close(btree, child_data)
            end
        end
    end
end

return RandomNode
