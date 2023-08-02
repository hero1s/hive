--property.lua
--[[提供对象属性机制
示例:
    local Object = class()
    prop = property(Object)
    prop:reader("id", 0)
    prop:accessor("name", "")
--]]

local type     = type
local select   = select
local tunpack  = table.unpack

local WRITER   = 1
local READER   = 2
local ACCESSOR = 3

local function clamp(n, min, max)
    if n < min then
        return min
    elseif n > max then
        return max
    end
    return n
end

local function on_prop_changed(object, name, value, ...)
    local f_prop_changed = object.on_prop_changed
    if f_prop_changed then
        f_prop_changed(object, value, name, ...)
    end
end

local function prop_accessor(class, name, default, mode)
    class.__props[name] = { default }
    if (mode & READER) == READER then
        class["get_" .. name] = function(self)
            return self[name]
        end
        if type(default) == "boolean" then
            class["is_" .. name] = class["get_" .. name]
        end
    end
    if (mode & WRITER) == WRITER then
        class["set_" .. name] = function(self, value, ...)
            if self[name] ~= value then
                self[name] = value
                on_prop_changed(self, name, value, ...)
            end
        end
    end
end

local function prop_wraper(class, name, fields)
    class["get_" .. name] = function(self)
        local res = {}
        for _, field in ipairs(fields) do
            res[#res + 1] = self[field]
        end
        return tunpack(res)
    end
    class["set_" .. name] = function(self, ...)
        local args = { ... }
        local num  = clamp(select("#", ...), 1, #fields)
        for i = 1, num do
            local key, value = fields[i], args[i]
            if self[key] ~= value then
                self[key] = value
                on_prop_changed(self, key, value)
            end
        end
    end
end

local property_reader   = function(self, name, default)
    prop_accessor(self.__class, name, default, READER)
end
local property_writer   = function(self, name, default)
    prop_accessor(self.__class, name, default, WRITER)
end
local property_wraper   = function(self, name, ...)
    prop_wraper(self.__class, name, { ... })
end
local property_accessor = function(self, name, default)
    prop_accessor(self.__class, name, default, ACCESSOR)
end

function property(class)
    local prop = {
        __class  = class,
        reader   = property_reader,
        writer   = property_writer,
        wraper   = property_wraper,
        accessor = property_accessor
    }
    return prop
end

