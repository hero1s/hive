--mixin.lua
--[[提供混入机制
示例:
    Execute = mixin()
    Listener = class(nil, Listener)
说明：
    mixin声明的成员自动附加到主类
    mixin声明的函数(除带下划线的私有方法)自动附加到主类
    mixin声明的__init/__release/__defer方法会随主类调用
备注：
    mixin类似多继承，但是继承强调i'am，而mixin强调i'can.
    mixin无法实例化，必须依附到class上，mixin函数的self都是属主class对象
--]]
local pcall        = pcall
local pairs        = pairs
local ssub         = string.sub
local dgetinfo     = debug.getinfo
local sformat      = string.format
local setmetatable = setmetatable
local log_err      = logger.err
local mixin_tpls   = _ENV.mixin_tpls or {}

local function index(mixin, field)
    return mixin.__methods[field]
end

local function newindex(mixin, field, value)
    mixin.__methods[field] = value
end

local function invoke(class, object, method, ...)
    if class.__super then
        invoke(class.__super, object, method, ...)
    end
    for _, mixin in ipairs(class.__mixins) do
        local mixin_method = mixin[method]
        if mixin_method then
            local ok, res = pcall(mixin_method, object, ...)
            if not ok then
                log_err("mixin: %s invoke '%s' failed: %s.", mixin.__source, method, res)
            end
        end
    end
end

--返回true表示所有接口都完成
local function collect(class, object, method, ...)
    if class.__super then
        if not collect(class.__super, object, method, ...) then
            return false
        end
    end
    for _, mixin in ipairs(class.__mixins) do
        local mixin_method = mixin[method]
        if mixin_method then
            local ok, res = pcall(mixin_method, object, ...)
            if (not ok) or (not res) then
                log_err("mixin: %s collect '%s' failed: %s.", mixin.__source, method, res)
                return false
            end
        end
    end
    return true
end

--代理一个类的所有接口，并检测接口是否实现
function implemented(class, mixins)
    class.invoke  = function(object, method, ...)
        invoke(object.__class, object, method, ...)
    end
    class.collect = function(object, method, ...)
        return collect(object.__class, object, method, ...)
    end
    for _, mixin in ipairs(mixins) do
        for name, value in pairs(mixin.__props) do
            --属性处理
            if class.__props[name] then
                log_err("the mixin default %s has repeat defined.", name)
            end
            class.__props[name] = value
        end
        for method in pairs(mixin.__methods) do
            if ssub(method, 1, 1) == "_" then
                --下划线前缀方法不代理
                goto continue
            end
            if class[method] then
                log_err("the mixin method %s has repeat defined.", method)
                goto continue
            end
            --接口代理
            class[method] = function(...)
                return mixin[method](...)
            end
            :: continue ::
        end
        local minixs        = class.__mixins
        minixs[#minixs + 1] = mixin
    end
end

local mixinMT = {
    __index    = index,
    __newindex = newindex
}

local function mixin_tostring(mixin)
    return sformat("mixin:%s", mixin.__source)
end

--接口定义函数
function mixin()
    local info      = dgetinfo(2, "S")
    local source    = info.short_src
    local mixin_tpl = mixin_tpls[source]
    if not mixin_tpl then
        local mixin        = {
            __props    = {},
            __methods  = {},
            __source   = source,
            __tostring = mixin_tostring,
        }
        mixin_tpl          = setmetatable(mixin, mixinMT)
        mixin_tpls[source] = mixin_tpl
    end
    return mixin_tpl
end
