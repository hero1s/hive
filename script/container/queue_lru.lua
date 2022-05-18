--queue_lru.lua

local QueueLRU = class()
local prop     = property(QueueLRU)
prop:reader("size", 0)
prop:reader("tuples", {})
prop:reader("oldest", nil)
prop:reader("newest", nil)
prop:accessor("max_size", 0)

function QueueLRU:__init(max_size)
    self.max_size = max_size
end

function QueueLRU:clear()
    self.size   = 0
    self.tuples = {}
    self.oldest = nil
    self.newest = nil
end

-- remove a tuple from linked list
function QueueLRU:cut(tuple)
    local tuple_prev = tuple.prev
    local tuple_next = tuple.next
    if tuple_prev then
        if tuple_next then
            tuple_prev.next = tuple_next
            tuple_next.prev = tuple_prev
        else
            -- tuple is the oldest element
            tuple_prev.next = nil
            self.oldest     = tuple_prev
        end
    else
        if tuple_next then
            -- tuple is the newest element
            tuple_next.prev = nil
            self.newest     = tuple_next
        else
            -- tuple is the only element
            self.newest = nil
            self.oldest = nil
        end
    end
    tuple.prev = nil
    tuple.next = nil
end

-- push a tuple to the newest end
function QueueLRU:push(tuple)
    if not self.newest then
        self.newest = tuple
        self.oldest = tuple
    else
        tuple.next       = self.newest
        self.newest.prev = tuple
        self.newest      = tuple
    end
end

function QueueLRU:del(key)
    local tuple = self.tuples[key]
    if tuple then
        self.tuples[key] = nil
        self:cut(tuple)
        self.size = self.size - 1
    end
end

function QueueLRU:get(key)
    local tuple = self.tuples[key]
    if tuple then
        self:cut(tuple)
        self:push(tuple)
        return tuple.value
    end
end

function QueueLRU:set(key, value)
    self:del(key)
    if value then
        local tuple      = { value = value, key = key }
        self.tuples[key] = tuple
        self.size        = self.size + 1
        self:push(tuple)
        if self.size > self.max_size then
            self:del(self.oldest.key)
        end
    end
end

--无序迭代器
function QueueLRU:iter()
    local index  = nil
    local tuples = self.tuples
    local function _iter()
        index = next(tuples, index)
        if index then
            local tuple = tuples[index]
            return tuple.key, tuple.value
        end
    end
    return _iter
end

--有序迭代器
function QueueLRU:iterator()
    local tuple = nil
    local function _iter()
        tuple = tuple and tuple.next or self.newest
        if tuple then
            return tuple.key, tuple.value
        end
    end
    return _iter
end

return QueueLRU