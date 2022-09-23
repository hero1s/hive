--node.lua

local SUCCESS   = luabt.SUCCESS

local BtNode = class()
local prop = property(BtNode)
prop:reader("name", "node")
prop:reader("opening", false)
prop:accessor("weight", 1)
function BtNode:__init()
end

--打开节点
function BtNode:open(tree)
    if not self.opening then
        tree:push(self)
        self.opening = true
    end
end

--返回是否执行完毕
function BtNode:run(tree)
    return SUCCESS
end

--关闭节点
function BtNode:close(tree)
    if self.opening then
        self:on_close(tree)
        self.opening = false
    end
end

--关闭回调
function BtNode:on_close(tree)
end

--[[
--需要支持中断的节点实现
function BtNode:on_interrupt(tree)
    return true
end
]]

return BtNode
