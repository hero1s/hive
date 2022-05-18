--queue.lua
local log_err = logger.err

local Queue = class()
local prop = property(Queue)
prop:reader("first", 1)
prop:reader("tail", 0)
prop:reader("datas", {})

function Queue:__init()
end

function Queue:clear()
    self.datas = {}
    self.first = 1
    self.tail = 0
end

function Queue:size()
    return self.tail - self.first + 1
end

function Queue:empty()
    return self.tail + 1 == self.first
end

function Queue:head()
    return self:elem(1)
end

function Queue:elem(pos)
    local index = self.first - 1 + pos
    if index > self.tail then
        return false
    end
    return true, self.datas[index]
end

function Queue:lpush(value)
    self.first = self.first - 1
    self.datas[self.first] = value
end

function Queue:lpop()
    local first, tail = self.first, self.tail
    if first > tail then
        return
    end
    local value = self.datas[first]
    self.datas[first] = nil
    self.first = first + 1
    return value
end

function Queue:rpush(value)
    self.tail = self.tail + 1
    self.datas[self.tail] = value
end

function Queue:rpop()
    local first, tail = self.first, self.tail
    if first > tail then
        return
    end
    local value = self.datas[tail]
    self.datas[tail] = nil
    self.tail = tail - 1
    return value
end

function Queue:insert(pos, value)
    local first, tail = self.first, self.tail
    if pos <= 0 or first + pos > tail + 2 then
        log_err("[Queue][insert]bad index to insert")
        return false
    end
    local realp = first + pos - 1
    if realp <= (first + tail) / 2 then
        for i = first, realp do
            self.data[i- 1] = self.data[i]
        end
        self.data[realp- 1] = value
        self.first = first - 1
    else
        for i = tail, realp, -1 do
            self.data[i+ 1] = self.data[i]
        end
        self.data[realp] = value
        self.tail = tail + 1
    end
    return true
end

function Queue:remove(pos)
    local first, tail = self.first, self.tail
    if pos <= 0 then
        log_err("[Queue][insert]bad index to remove")
        return
    end
    if first + pos - 1 > tail then
        return
    end
    local realp = first + pos - 1
    local value = self.data[realp]
    if self:size() == 1 then
        self:clear()
        return value
    end
    if realp <= (first + tail) / 2 then
        for i = realp, first, -1 do
            self.data[i] = self.data[i - 1]
        end
        self.first = first + 1
    else
        for i = realp, tail do
            self.data[i] = self.data[i + 1]
        end
        self.tail = tail - 1
    end
    return value
end

--迭代器
function Queue:iter()
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

return Queue
