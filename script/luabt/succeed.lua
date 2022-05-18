--succeed.lua
local RUNNING      = luabt.BTConst.RUNNING
local SUCCESS      = luabt.BTConst.SUCCESS

local node_execute = luabt.node_execute

local SucceedNode  = class()
function SucceedNode:__init(node)
    self.name  = "always_succeed"
    self.child = node
end

function SucceedNode:run(btree, node_data)
    if self.child then
        local status = node_execute(self.child, btree, node_data.__level + 1)
        if status == RUNNING then
            return status
        else
            return SUCCESS
        end
    end
    return SUCCESS
end

function SucceedNode:close(btree)
    if self.child then
        local node      = self.child
        local node_data = btree[node]
        if node_data and node_data.is_open then
            node_data.is_open = false
            if node.close then
                node:close(btree, node_data)
            end
        end
    end
end

return SucceedNode
