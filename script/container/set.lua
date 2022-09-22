-- 无序set
local Set = class()
local prop = property(Set)
prop:reader("size",0)
prop:reader("data",{})

function Set:__init()

end

function Set:insert(value)
    -- assert(not self._data[value], string.format("set: value %s already exist", tostring(value)))
    if not self.data[value] then
        self.data[value] = true
        self.size = self.size + 1
        return true
    end
    return false
end

function Set:remove(value)
    --assert(self._data[value], "set:attemp remove unexist value")
    if self.data[value] then
        self.data[value] = nil
        self.size = self.size - 1
        return value
    end
    return false
end

function Set:has(value)
    return self.data[value]
end

function Set:foreach(f, ...)
    for k, v in pairs(self.data) do
        if v then
            f(k, ...)
        end
    end
end

function Set:at(pos)
    local n = 0
    for k, _ in pairs(self.data) do
        n = n + 1
        if n == pos then
            return k
        end
    end
    return nil
end

function Set:clear()
    for k, _ in pairs(self.data) do
        self.data[k] = nil
    end
    self.size = 0
end

function Set:to_array()
    local dst = {}
    for _, value in pairs(self.data) do
        dst[#dst + 1] = value
    end
    return dst
end

return Set
