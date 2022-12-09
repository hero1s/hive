--class.lua
local type         = type
local load         = load
local pcall        = pcall
local pairs        = pairs
local ipairs       = ipairs
local rawget       = rawget
local rawset       = rawset
local tostring     = tostring
local ssub         = string.sub
local sformat      = string.format
local dgetinfo     = debug.getinfo
local getmetatable = getmetatable
local setmetatable = setmetatable

--类模板
local class_tpls   = _ENV.class_tpls or {}

local function deep_copy(src, dst)
    local ndst = dst or {}
    for key, value in pairs(src or {}) do
        if is_class(value) then
            ndst[key] = value()
        elseif (type(value) == "table") then
            ndst[key] = deep_copy(value)
        else
            ndst[key] = value
        end
    end
    return ndst
end

local function class_raw_call(method, class, object, ...)
    local func = rawget(class.__vtbl, method)
    if type(func) == "function" then
        func(object, ...)
    end
end

local function class_mixin_call(method, class, object, ...)
    for _, mixin in ipairs(class.__mixins) do
        local func = rawget(mixin.__methods, method)
        if type(func) == "function" then
            func(object, ...)
        end
    end
end

local function object_init(class, object, ...)
    if class.__super then
        object_init(class.__super, object, ...)
    end
    class_raw_call("__init", class, object, ...)
    class_mixin_call("__init", class, object, ...)
    return object
end

local function object_release(class, object, ...)
    class_mixin_call("__release", class, object, ...)
    class_raw_call("__release", class, object, ...)
    if class.__super then
        object_release(class.__super, object, ...)
    end
end

local function object_defer(class, object, ...)
    class_mixin_call("__defer", class, object, ...)
    class_raw_call("__defer", class, object, ...)
    if class.__super then
        object_defer(class.__super, object, ...)
    end
end

local function object_props(class, object)
    if class.__super then
        object_props(class.__super, object)
    end
    local props = deep_copy(class.__props)
    for name, param in pairs(props) do
        object[name] = param[1]
    end
end

local function object_tostring(object)
    if type(object.tostring) == "function" then
        return object:tostring()
    end
    return sformat("class(%s)[%s]", object.__addr, object.__source)
end

local function object_constructor(class)
    local obj = {}
    object_props(class, obj)
    obj.__addr = ssub(tostring(obj), 8)
    setmetatable(obj, class.__vtbl)
    return obj
end

local function object_super(obj)
    return obj.__super
end

local function object_source(obj)
    return obj.__source
end

local function mt_class_new(class, ...)
    if rawget(class, "__singleton") then
        local object = rawget(class, "__inst")
        if not object then
            object = object_constructor(class)
            rawset(class, "__inst", object)
            rawset(class, "inst", function()
                return object
            end)
            object_init(class, object, ...)
        end
        return object
    else
        local object = object_constructor(class)
        return object_init(class, object, ...)
    end
end

local function mt_class_index(class, field)
    return class.__vtbl[field]
end

local function mt_class_newindex(class, field, value)
    class.__vtbl[field] = value
end

local function mt_object_release(obj)
    object_release(obj.__class, obj)
end

local function mt_object_defer(obj)
    object_defer(obj.__class, obj)
end

local classMT = {
    __call     = mt_class_new,
    __index    = mt_class_index,
    __newindex = mt_class_newindex
}

local function class_constructor(class, super, ...)
    local info      = dgetinfo(2, "S")
    local source    = info.short_src
    local class_tpl = class_tpls[source]
    if not class_tpl then
        local vtbl   = {
            __class    = class,
            __super    = super,
            __source   = source,
            __tostring = object_tostring,
            super      = object_super,
            source     = object_source,
        }
        vtbl.__index = vtbl
        vtbl.__gc    = mt_object_release
        vtbl.__close = mt_object_defer
        if super then
            setmetatable(vtbl, { __index = super })
        end
        class.__vtbl   = vtbl
        class.__super  = super
        class.__props  = {}
        class.__mixins = {}
        class_tpl      = setmetatable(class, classMT)
        implemented(class, ...)
        class_tpls[source] = class_tpl
    end
    return class_tpl
end

function class(super, ...)
    return class_constructor({}, super, ...)
end

function singleton(super, ...)
    return class_constructor({ __singleton = true }, super, ...)
end

function super(value)
    return value.__super
end

function is_class(class)
    return classMT == getmetatable(class)
end

function classof(object)
    return object.__class
end

function is_subclass(class, super)
    while class do
        if class == super then
            return true
        end
        class = rawget(class, "__super")
    end
    return false
end

function instanceof(object, class)
    if not object or not class then
        return false
    end
    local obj_class = object.__class
    if obj_class then
        return is_subclass(obj_class, class)
    end
    return false
end

function is_singleton(object)
    local class = classof(object)
    return class and rawget(class, "__singleton")
end

function conv_class(name)
    local runtime = sformat("local obj = %s() return obj", name)
    local ok, obj = pcall(load(runtime))
    if ok then
        return obj
    end
end

