--weight_sequence.lua
local ipairs        = ipairs

local FAIL          = luabt.BTConst.FAIL
local RUNNING       = luabt.BTConst.RUNNING
local SUCCESS       = luabt.BTConst.SUCCESS

local node_execute  = luabt.node_execute
local node_reorder  = luabt.node_reorder

local WSequenceNode = class()
--#weight == select("#", ...))
function WSequenceNode:__init(weight, ...)
    self.name         = "weight_sequence"
    self.weight       = weight
    self.children     = { ... }
    self.total_weight = 0
    for i = 1, #weight do
        self.total_weight = self.total_weight + weight[i]
    end
end

function WSequenceNode:open(_, node_data)
    node_data.runningChild = 1
    if not node_data.indexes then
        local indexes = {}
        for i = 1, #self.children do
            indexes[#indexes + 1] = i
        end
        node_data.indexes = indexes
    end
    node_reorder(node_data.indexes, self.weight, self.total_weight)
end

function WSequenceNode:run(btree, node_data)
    local child = node_data.runningChild
    for i = child, #node_data.indexes do
        local index  = node_data.indexes[i]
        local status = node_execute(self.children[index], btree, node_data.__level + 1)
        if status == FAIL then
            return status
        end
        if status == RUNNING then
            node_data.runningChild = i
            return status
        end
    end
    return SUCCESS
end

function WSequenceNode:close(btree, node_data)
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

return WSequenceNode
