--failed.lua
local FAIL         = luabt.BTConst.FAIL
local RUNNING      = luabt.BTConst.RUNNING
local node_execute = luabt.node_execute

local FailedNode   = class()
function FailedNode:__init(node)
    self.name  = "always_fail"
    self.child = node
end

function FailedNode:run(btree, node_data)
    if self.child then
        local status = node_execute(self.child, btree, node_data.__level + 1)
        if status == RUNNING then
            return status
        else
            return FAIL
        end
    end
    return FAIL
end

function FailedNode:close(btree)
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

return FailedNode
