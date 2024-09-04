--math.lua
local mfloor     = math.floor
local mtointeger = math.tointeger
local msqrt      = math.sqrt
local random     = math.random
local tconcat    = table.concat
local tinsert    = table.insert

math_ext         = _ENV.math_ext or {}

--四舍五入
function math_ext.round(n)
    return mfloor(0.5 + n)
end

--随机函数
function math_ext.random(a, b)
    if a then
        return random(a, b)
    end
    return random(0xffff, 0xfffffff)
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

-- 返回指定长度的字符串(数字+字母)
local WORD_ARR = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 0,
    'a', 'b', 'c', 'd', 'e', 'f', 'g',
    'h', 'i', 'j', 'k', 'l', 'm', 'n',
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z'
}
function math_ext.random_str(len)
    local result_arr = {}
    for i = 1, len do
        tinsert(result_arr, WORD_ARR[random(1, #WORD_ARR)])
    end

    return tconcat(result_arr, "")
end

-- 用于从数组中随机多个，数组要发生变化，取数值前cnt个即为结果
function math_ext.random_some(arr, cnt)
    if cnt >= #arr then
        return
    end
    for i = 1, cnt do
        local x   = random(i, #arr)
        local tmp = arr[i]
        arr[i]    = arr[x]
        arr[x]    = tmp
    end
end
