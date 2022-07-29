--math.lua
local mfloor     = math.floor
local mtointeger = math.tointeger

math_ext         = _ENV.math_ext or {}

--取整
function math_ext.round(n)
    return mfloor(0.5 + n)
end

--保留小数位
function math_ext.cut_tail(value, multiple, cut)
    local n = 10 ^ multiple
    if not cut then
        return mfloor(value * n + 0.5) / n
    else
        return mfloor(value * n) / n
    end
end

--区间检查
function math_ext.region(n, min, max)
    if n < min then
        return min
    elseif n > max then
        return max
    end
    return n
end

function math_ext.conv_integer(v)
    return mtointeger(v) or v
end

function math_ext.conv_number(v)
    return mtointeger(v) or tonumber(v) or v
end

