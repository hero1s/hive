--defer.lua
local tinsert = table.insert

local Defer   = class()
local prop    = property(Defer)
prop:reader("triggers", {})

function Defer:__init(handler)
    if handler then
        tinsert(self.triggers, handler)
    end
end

function Defer:register(handler)
    tinsert(self.triggers, handler)
end

function Defer:__defer()
    for _, handler in ipairs(self.triggers) do
        handler()
    end
    self.triggers = {}
end

function Defer:reset()
    self.triggers = {}
end

return Defer
