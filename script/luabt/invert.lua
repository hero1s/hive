--invert.lua

local FAIL         = luabt.BTConst.FAIL
local SUCCESS      = luabt.BTConst.SUCCESS
local RUNNING      = luabt.BTConst.RUNNING
local node_execute = luabt.node_execute

local InvertNode   = class()
function InvertNode:__init(node)
    self.name  = "invert"
    self.child = node
end

function InvertNode:run(btree, node_data)
    local status = node_execute(self.child, btree, node_data.__level + 1)
    if status == RUNNING then
        return status
    elseif status == SUCCESS then
        return FAIL
    else
        return SUCCESS
    end
end

function InvertNode:close(btree)
    local node      = self.child
    local node_data = btree[node]
    if node_data and node_data.is_open then
        node_data.is_open = false
        if node.close then
            node:close(btree, node_data)
        end
    end
end

return InvertNode
