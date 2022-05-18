--sequence.lua
local ipairs       = ipairs
local SUCCESS      = luabt.BTConst.SUCCESS

local node_execute = luabt.node_execute

local SequenceNode = class()
function SequenceNode:__init(...)
    self.name     = "sequence"
    self.children = { ... }
end

function SequenceNode:run(btree, node_data)
    for _, node in ipairs(self.children) do
        local status = node_execute(node, btree, node_data.__level + 1)
        if status ~= SUCCESS then
            return status
        end
    end
    return SUCCESS
end

function SequenceNode:close(btree)
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

return SequenceNode
