--condition.lua
local ipairs        = ipairs
local SUCCESS       = luabt.BTConst.SUCCESS
local node_execute  = luabt.node_execute

local ConditionNode = class()
function ConditionNode:__init(cond, success, failed)
    self.name     = "condition"
    self.cond     = cond
    self.failed   = failed
    self.success  = success
    self.children = { cond, failed, success }
end

function ConditionNode:run(btree, node_data)
    local status = node_execute(self.cond, btree, node_data.__level + 1)
    if status == SUCCESS then
        return node_execute(self.success, btree, node_data.__level + 1)
    else
        return node_execute(self.failed, btree, node_data.__level + 1)
    end
end

function ConditionNode:close(btree)
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

return ConditionNode
