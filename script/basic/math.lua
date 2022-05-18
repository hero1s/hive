--math.lua
local mfloor     = math.floor
local mtointeger = math.tointeger

function math_ext.round(n)
    return mfloor(0.5 + n)
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

