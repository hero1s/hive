
local Array = class()
local prop = property(Array)
prop:reader("cur",0)
prop:reader("data",{})

function Array:__init()

end

function Array:push(value)
    self.cur = self.cur + 1
    self.data[self.cur] = value
end

function Array:pop()
    assert(self.cur>0,"array:attemp pop empty table")
    self.cur = self.cur - 1
    return self.data[self.cur+1]
end

function Array:clear()
    self.cur = 0
end

function Array:size()
    return self.cur
end

function Array:data()
    return self.data
end

function Array:foreach(f)
    for i=1,self.cur do
        f(self.data[i])
    end
end

return Array
