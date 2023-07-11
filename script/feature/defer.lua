--defer.lua

local Defer = class()
local prop = property(Defer)
prop:reader("handler", nil)

function Defer:__init(handler)
    self.handler = handler
end

function Defer:__defer()
    if self.handler then
        self.handler()
    end
end

return Defer
