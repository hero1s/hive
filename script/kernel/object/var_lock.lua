--成员变量锁
local VarLock = class()
local prop    = property(VarLock)
prop:reader("host", nil)
prop:reader("key", nil)

function VarLock:__init(host, key)
    self.host      = host
    self.key       = key
    self.host[key] = true
end

function VarLock:__defer()
    self.host[self.key] = false
end

return VarLock
