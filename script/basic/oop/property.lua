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
local tunpack  = table.unpack
local tsort    = table.sort
local log_err  = logger.err
local WRITER   = 1
local READER   = 2
local ACCESSOR = 3

local function unequal(a, b)
    if type(a) ~= "table" then
        return a ~= b
    end
    for k, v in pairs(a) do
        if b[k] ~= v then
            return true
        end
    end
    return false
end

local function on_prop_changed(object, name, value)
    local f_prop_changed = object.on_prop_changed
    if f_prop_changed then
        f_prop_changed(object, value, name)
    end
end

local function prop_accessor(class, name, default, mode, watch)
    class.__props[name] = tpack(default, mode, watch)
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
            local n = select("#", ...)
            if n > 0 then
                log_err("set prop args is so more!")
            end
            if unequal(self[name], value) then
                self[name] = value
                if watch then
                    on_prop_changed(self, name, value)
                end
            end
        end
    end
end

local function prop_unfold(class, name, sub_keys)
    local prop_inf = class.__props[name]
    if not prop_inf then
        return
    end
    local default, mode, watch = tunpack(prop_inf)
    if default and type(default) ~= "table" then
        return
    end
    if not sub_keys then
        sub_keys = {}
        for key in pairs(default) do
            sub_keys[#sub_keys + 1] = key
        end
        tsort(sub_keys, function(a, b)
            return a < b
        end)
    end
    if #sub_keys < 2 then
        return
    end
    if (mode & READER) == READER then
        class["get_" .. name] = function(self, unfold)
            local prop = self[name]
            if prop and unfold then
                local tres = {}
                for i, key in pairs(sub_keys) do
                    tres[i] = prop[key]
                end
                return tunpack(tres, 1, #sub_keys)
            end
            return prop
        end
        for _, key in pairs(sub_keys) do
            class["get_" .. name .. "_" .. key] = function(self)
                local prop = self[name]
                if prop then
                    return prop[key]
                end
            end
        end
    end
    if (mode & WRITER) == WRITER then
        for _, key in pairs(sub_keys) do
            class["set_" .. name .. "_" .. key] = function(self, value)
                local prop = self[name]
                if prop and unequal(prop[key], value) then
                    prop[key] = value
                    if watch then
                        on_prop_changed(self, name, prop)
                    end
                end
            end
        end
        class["set_" .. name] = function(self, ...)
            local args, changed = { ... }
            local n             = select("#", ...)
            if n == 1 then
                local value = args[1]
                if type(value) == "table" and unequal(self[name], value) then
                    self[name] = value
                    changed    = value
                end
            else
                if not self[name] then
                    self[name] = {}
                end
                local prop = self[name]
                for i = 1, n do
                    local key, value = sub_keys[i], args[i]
                    if key and unequal(prop[key], value) then
                        prop[key] = value
                        if not changed then
                            changed = prop
                        end
                    end
                end
            end
            if watch and changed then
                on_prop_changed(self, name, changed)
            end
        end
    end
end

local property_reader   = function(self, name, default)
    prop_accessor(self.__class, name, default, READER)
end
local property_writer   = function(self, name, default, watch)
    prop_accessor(self.__class, name, default, WRITER, watch)
end
local property_accessor = function(self, name, default, watch)
    prop_accessor(self.__class, name, default, ACCESSOR, watch)
end

local property_unfold   = function(self, name, sub_keys)
    prop_unfold(self.__class, name, sub_keys)
end

function property(class)
    local prop = {
        __class  = class,
        reader   = property_reader,
        writer   = property_writer,
        accessor = property_accessor,
        unfold   = property_unfold,
    }
    return prop
end

