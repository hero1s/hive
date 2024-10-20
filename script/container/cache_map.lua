--cache_map.lua

local CacheMap = class()
local prop     = property(CacheMap)
prop:reader("cache", nil)
function CacheMap:__init(max_size)
    self.cache = lcache.new(max_size)
end

function CacheMap:clear()
    return self.cache:clear()
end

function CacheMap:del(key)
    return self.cache:del(key)
end

function CacheMap:get(key)
    return self.cache:get(key)
end

function CacheMap:set(key, value)
    if not value then
        return self.cache:del(key)
    end
    return self.cache:set(key, value)
end

function CacheMap:exist(key)
    return self.cache:exist(key)
end

function CacheMap:size()
    return self.cache:size()
end

return CacheMap