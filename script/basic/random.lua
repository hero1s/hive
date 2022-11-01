--random.lua
local mrandom       = math.random
local tinsert       = table.insert
local tunpack       = table.unpack
local tremove       = table.remove

local Random = class()
local prop = property(Random)
prop:reader("weight", 0)            --权重
prop:reader("childs", {})           --childs
prop:reader("stand_alone", false)   --是否独立随机

function Random:__init()
end

--轮盘随机添加子对象
--excl：命中后是否淘汰，可以用于控制保底策略
function Random:add_alone(obj, rate)
    self.stand_alone = true
    tinsert(self.childs, { obj, rate })
end

--轮盘随机添加子对象
--excl：命中后是否淘汰，可以用于控制保底策略
function Random:add_wheel(obj, wght, excl)
    self.stand_alone = false
    self.weight = self.weight + wght
    tinsert(self.childs, { obj, wght, excl })
end

--万分比是否命中
function Random:ttratio(val)
    return val > mrandom(1, 10000)
end

--执行独立随机，返回命中对象
function Random:rand_alone()
    local targets = {}
    for i, child in pairs(self.childs) do
        local obj, rate = tunpack(child)
        if rate > mrandom(1, 10000) then
            tinsert(targets, obj)
        end
    end
    return targets
end

--执行轮盘随机，返回命中对象
function Random:rand_wheel()
    if self.weight <= 0 then
        return
    end
    local weight = mrandom(1, self.weight)
    for i, child in pairs(self.childs) do
        local obj, wght, excl = tunpack(child)
        if wght > weight then
            if excl then
                tremove(self.childs, i)
            end
            return { obj }
        end
        weight = weight - wght
    end
end

--执行随机，返回命中对象
function Random:execute()
    if self.stand_alone then
        return self:rand_alone()
    end
    return self:rand_wheel()
end

return Random
