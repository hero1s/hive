--parallel.lua
local ipairs        = ipairs
local FAIL          = luabt.FAIL
local WAITING       = luabt.WAITING
local SUCCESS       = luabt.SUCCESS
local FAIL_ONE      = luabt.FAIL_ONE
local FAIL_ALL      = luabt.FAIL_ALL
local SUCCESS_ALL   = luabt.SUCCESS_ALL
local SUCCESS_ONE   = luabt.SUCCESS_ONE

local Node          = luabt.Node

local ParallelNode = class(Node)
function ParallelNode:__init(fail_policy, success_policy, ...)
    self.name = "parallel"
    self.fail_count = 0
    self.fail_policy = fail_policy
    self.success_policy = success_policy
    self.childs = {...}
    self.index = 0
end

function ParallelNode:run(tree)
    local status = tree:get_status()
    if status == FAIL then
        self.fail_count = self.fail_count + 1
        if self.fail_policy == FAIL_ONE or self.success_policy == SUCCESS_ALL then
            return FAIL
        end
    end
    if status == SUCCESS and self.success_policy == SUCCESS_ONE then
        return SUCCESS
    end
    local child_count = #self.childs
    local index = self.index + 1
    if index > child_count then
        if self.fail_count < child_count and self.success_policy == FAIL_ALL then
            return SUCCESS
        end
        return FAIL
    end
    self.childs[index]:open(tree)
    self.index = index
    return WAITING
end

function ParallelNode:on_close(tree)
    self.index = 0
    self.fail_count = 0
    for _, child in ipairs(self.childs) do
        child:close(tree)
    end
end

return ParallelNode
