--math.lua
local mfloor     = math.floor
local mtointeger = math.tointeger
local msqrt      = math.sqrt
local mrandom    = math.random

math_ext         = _ENV.math_ext or {}

--四舍五入
function math_ext.round(n)
    return mfloor(0.5 + n)
end

--随机函数
function math_ext.rand(a, b)
    return mrandom(a, b)
end

function math_ext.random()
    return mrandom(0xffff, 0xfffffff)
end

--计算距离
function math_ext.distance(x, z, nx, nz)
    local dx, dz = nx - x, nz - z
    return msqrt(dx * dx + dz * dz)
end

--判断距离
function math_ext.judg_dis(x, z, nx, nz, r)
    local dx, dz = nx - x, nz - z
    return dx * dx + dz * dz < r * r
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
    return mtointeger(tonumber(v)) or 0
end

function math_ext.conv_number(v)
    return mtointeger(v) or tonumber(v) or 0
end

