--luabt.lua
luabt = luabt or {}

import("luabt/const.lua")
import("luabt/node.lua")
local pairs        = pairs
local node_execute = luabt.node_execute
local SUCCESS      = luabt.BTConst.SUCCESS

local BtTrace      = import("luabt/trace.lua")
local NODE_TYPE    = luabt.NODE_TYPE
local NODE_CLASS   = {
    [NODE_TYPE.SUCCESS]         = import("luabt/succeed.lua"),
    [NODE_TYPE.FAILED]          = import("luabt/failed.lua"),
    [NODE_TYPE.INVERT]          = import("luabt/invert.lua"),
    [NODE_TYPE.RANDOM]          = import("luabt/random.lua"),
    [NODE_TYPE.PRIORITY]        = import("luabt/priority.lua"),
    [NODE_TYPE.PARALLEL]        = import("luabt/parallel.lua"),
    [NODE_TYPE.CONDITION]       = import("luabt/condition.lua"),
    [NODE_TYPE.SEQUENCE]        = import("luabt/sequence.lua"),
    [NODE_TYPE.MEM_SEQUENCE]    = import("luabt/mem_sequence.lua"),
    [NODE_TYPE.MEM_PRIORITY]    = import("luabt/mem_priority.lua"),
    [NODE_TYPE.WEIGHT_SEQUENCE] = import("luabt/weight_sequence.lua"),
    [NODE_TYPE.WEIGHT_PRIORITY] = import("luabt/weight_priority.lua"),
}

--创建节点
luabt.create_node  = function(node_type, ...)
    local node_class = NODE_CLASS[node_type]
    if node_class then
        return node_class(...)
    end
end

local LuaBT        = class()

-- bt tree 实例：保存树的状态和黑板, [node] -> {is_open:boolean, ...}
-- @param robot     The robot to control
-- @param root      The behaviour tree root
function LuaBT:__init(robot, root)
    self.robot      = robot
    self.root       = root
    self.open_nodes = {}    -- 上一次 tick 运行中的节点
    self.last_open  = {}
    self.frame      = 0          -- 帧数
    self.trace      = BtTrace()
end

function LuaBT:tick()
    self.trace:clear()
    local status    = node_execute(self.root, self, 0)
    -- close open nodes if necessary
    local openNodes = self.open_nodes
    local lastOpen  = self.last_open
    for node in pairs(lastOpen) do
        local node_data = self[node]
        if not openNodes[node] and node_data.is_open then
            node_data.is_open = false
            if node.close then
                node:close(self, node_data)
            end
        end
        lastOpen[node] = nil
    end
    self.last_open  = openNodes
    self.open_nodes = lastOpen  -- empty table
    self.frame      = self.frame + 1
    return status == SUCCESS
end

function LuaBT:trace()
    self.trace:trace()
end

return LuaBT