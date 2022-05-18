--mem_priority.lua
local ipairs        = ipairs
local FAIL          = luabt.BTConst.FAIL
local SUCCESS       = luabt.BTConst.SUCCESS
local RUNNING       = luabt.BTConst.RUNNING
local node_execute  = luabt.node_execute

local MPriorityNode = class()
function MPriorityNode:__init(...)
    self.name     = "mem_priority"
    self.children = { ... }
end

function MPriorityNode:open(_, node_data)
    node_data.runningChild = 1
end

function MPriorityNode:run(btree, node_data)
    local child = node_data.runningChild
    for i = child, #self.children do
        local status = node_execute(self.children[i], btree, node_data.__level + 1)
        if status == SUCCESS then
            return status
        end
        if status == RUNNING then
            node_data.runningChild = i
            return status
        end
    end
    return FAIL
end

function MPriorityNode:close(btree, node_data)
    node_data.runningChild = 1
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

return MPriorityNode
