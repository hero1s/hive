--luabt.lua
local pairs     = pairs
local tremove   = table.remove

luabt = {
    -- Node Status
    WAITING     = 0,
    SUCCESS     = 1,
    FAIL        = 2,
    RUNNING     = 3,
    -- Parallel Policy
    SUCCESS_ONE = 1,    -- success when one child success
    SUCCESS_ALL = 2,    -- success when all children success
    FAIL_ONE    = 3,    -- fail when one child fail
    FAIL_ALL    = 4,    -- fail when all children fail
}

luabt.Node      = require("luabt.node")
luabt.Failed    = require("luabt.failed")
luabt.Invert    = require("luabt.invert")
luabt.Random    = require("luabt.random")
luabt.Repeat    = require("luabt.repeat")
luabt.Select    = require("luabt.select")
luabt.Succeed   = require("luabt.succeed")
luabt.Sequence  = require("luabt.sequence")
luabt.Parallel  = require("luabt.parallel")
luabt.WSelect   = require("luabt.wselect")
luabt.WSequence = require("luabt.wsequence")
luabt.Condition = require("luabt.condition")

local WAITING   = luabt.WAITING
local RUNNING   = luabt.RUNNING
local SUCCESS   = luabt.SUCCESS

local LuaBT = class()
local prop = property(LuaBT)
prop:reader("frame", 0)
prop:reader("root", nil)
prop:reader("robot", nil)
prop:reader("nodes", {})
prop:reader("history", {})
prop:reader("interrupts", {})
prop:accessor("args", {})
prop:accessor("blackboard", {})
prop:accessor("tracing", false)
prop:accessor("status", WAITING)

function LuaBT:__init(robot, root)
    self.robot = robot
    self.root = root
end

function LuaBT:tick()
    self.frame = self.frame + 1
    for _, node in pairs(self.interrupts) do
        if node:on_interrupt(self) then
            self:interrupt(node)
            break
        end
    end
    while #self.nodes > 0 do
        local node = self.nodes[#self.nodes]
        self.status = node:run(self)
        self:trace(node)
        if self.status == RUNNING then
            break
        end
        if self.status ~= WAITING then
            --进入子节点
            self:pop(node)
        end
    end
    local succes = (self.status == SUCCESS)
    if self.status ~= RUNNING then
        self:reset()
    end
    return succes
end

--压入节点
function LuaBT:push(node)
    self.nodes[#self.nodes + 1] = node
    if node.on_interrupt then
        self.interrupts[#self.interrupts + 1] = node
    end
end

--弹出节点
function LuaBT:pop(node)
    if self.nodes[#self.nodes] == node then
        node:close(self)
        tremove(self.nodes)
        if self.interrupts[#self.interrupts] == node then
            tremove(self.interrupts)
        end
    end
end

--清空
function LuaBT:reset()
    self.frame = 0
    self.nodes = {}
    self.history = {}
    self.interrupts = {}
    self.status = WAITING
    self.root:open(self)
end

--中断
function LuaBT:interrupt(node)
    for i = #self.nodes, 1, -1 do
        local curr = self.nodes[i]
        if curr ~= node then
            curr:close(self)
        end
    end
    for i = #self.interrupts, 1, -1 do
        local curr = self.interrupts[i]
        if curr ~= node then
            curr:close(self)
        end
    end
end

--调试
function LuaBT:trace(node)
    if self.tracing then
        local hnode = { name = node.name, frame = self.frame }
        self.history[#self.history + 1] = hnode
    end
end

--打印流程图
function LuaBT:dump()
    for _, node in pairs(self.history) do
        print("lua bt history node:%s, frame:%s", node.node.name, node.frame)
    end
end

return LuaBT
