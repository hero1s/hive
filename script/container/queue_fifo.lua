--queue_fifo.lua

local QueueFIFO = class()
local prop = property(QueueFIFO)
prop:reader("first", 1)
prop:reader("tail", 0)
prop:reader("datas", {})

function QueueFIFO:__init()
end

function QueueFIFO:clear()
    self.datas = {}
    self.first = 1
    self.tail = 0
end

function QueueFIFO:size()
    return self.tail - self.first + 1
end

function QueueFIFO:empty()
    return self.tail + 1 == self.first
end

function QueueFIFO:head()
    return self:elem(1)
end

function QueueFIFO:elem(pos)
    local index = self.first - 1 + pos
    if index > self.tail then
        return
    end
    return self.datas[index]
end

function QueueFIFO:push(value)
    self.tail = self.tail + 1
    self.datas[self.tail] = value
end

function QueueFIFO:pop()
    local first, tail = self.first, self.tail
    if first > tail then
        return
    end
    local value = self.datas[first]
    self.datas[first] = nil
    self.first = first + 1
    return value
end

--迭代器
function QueueFIFO:iter()
    local datas = self.datas
    local index, tail = self.first - 1, self.tail
    local function _iter()
        index = index + 1
        if index <= tail then
            return index - self.first + 1, datas[index]
        end
    end
    return _iter
end

return QueueFIFO