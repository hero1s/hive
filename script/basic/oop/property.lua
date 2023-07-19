--property.lua
--[[提供对象属性机制
示例:
    local Object = class()
    prop = property(Object)
    prop:reader("id", 0)
    prop:accessor("name", "")
--]]

local type     = type
local tpack    = table.pack

local WRITER   = 1
local READER   = 2
local ACCESSOR = 3

local function on_prop_changed(object, name, value, ...)
    local f_prop_changed = object.on_prop_changed
    if f_prop_changed then
        f_prop_changed(object, value, name, ...)
    end
end

local function prop_accessor(class, name, default, mode)
    class.__props[name] = tpack(default)
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
            if self[name] ~= value or type(value) == "table" then
                self[name] = value
                on_prop_changed(self, name, value, ...)
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
local property_accessor = function(self, name, default)
    prop_accessor(self.__class, name, default, ACCESSOR)
end

function property(class)
    local prop = {
        __class  = class,
        reader   = property_reader,
        writer   = property_writer,
        accessor = property_accessor
    }
    return prop
end

