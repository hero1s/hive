--table.lua
local type    = type
local pairs   = pairs
local ipairs  = ipairs
local tsort   = table.sort
local mrandom = math.random
local tremove = table.remove

local function trandom(tab)
    local keys = {}
    for k in pairs(tab) do
        keys[#keys + 1] = k
    end
    if #keys > 0 then
        local key = keys[mrandom(#keys)]
        return key, tab[key]
    end
end

local function trandom_array(tab)
    if tab and #tab > 0 then
        return tab[mrandom(#tab)]
    end
end

local function tindexof(tab, val)
    for i, v in pairs(tab) do
        if v == val then
            return i
        end
    end
end

local function tis_array(tab)
    if not tab or type(tab) ~= "table" then
        return false
    end
    local idx = 1
    for key in pairs(tab) do
        if key ~= idx then
            return false
        end
        idx = idx + 1
    end
    return true
end

local function tsize(t, filter)
    local c = 0
    for _, v in pairs(t or {}) do
        if not filter or filter(v) then
            c = c + 1
        end
    end
    return c
end

local function tcopy(src, dst)
    local ndst = dst or {}
    for field, value in pairs(src or {}) do
        ndst[field] = value
    end
    return ndst
end

local function tdeep_copy(src, dst)
    local ndst = dst or {}
    for key, value in pairs(src or {}) do
        if is_class(value) then
            ndst[key] = value()
        elseif (type(value) == "table") then
            ndst[key] = tdeep_copy(value)
        else
            ndst[key] = value
        end
    end
    return ndst
end

local function tdelete(stab, val, num)
    num = num or 1
    for i = #stab, 1, -1 do
        if stab[i] == val then
            tremove(stab, i)
            num = num - 1
            if num <= 0 then
                break
            end
        end
    end
    return stab
end

local function tjoin(src, dst)
    local ndst = dst or {}
    for _, v in pairs(src) do
        ndst[#ndst + 1] = v
    end
    return ndst
end

local function tmerge(src, dst)
    local ndst = dst or {}
    for key, v in pairs(src) do
        ndst[key] = v
    end
    return ndst
end

local function tpush(dst, ...)
    local args = { ... }
    local n    = select("#", ...)
    for i = 1, n do
        dst[#dst + 1] = args[i]
    end
    return dst
end

local function tdiff(src, dst)
    local add, del = {}, {}
    for k, v in pairs(src) do
        if not dst[k] then
            del[k] = v
        end
    end
    for k, v in pairs(dst) do
        if not src[k] then
            add[k] = v
        end
    end
    return add, del
end

-- map中的value抽出来变成array (会丢失key信息)
local function tarray(src)
    local dst = {}
    for _, value in pairs(src or {}) do
        dst[#dst + 1] = value
    end
    return dst
end

-- map转为{key,value}类型的array
local function tkvarray(src)
    local dst = {}
    for key, value in pairs(src or {}) do
        dst[#dst + 1] = { key, value }
    end
    return dst
end

-- {key,value}array转为map
local function tmap(src)
    local dst = {}
    for _, pair in pairs(src or {}) do
        dst[pair[1]] = pair[2]
    end
    return dst
end

local function tmapsort(src)
    local dst = tkvarray(src)
    tsort(dst, function(a, b)
        return a[1] < b[1]
    end)
    return dst
end

local function fastremove(object, fn)
    local n
    for i, value in ipairs(object) do
        if fn(value) then
            n = i
            break
        end
    end
    if n then
        local v
        if #object == 1 then
            v = tremove(object)
        else
            if n == #object then
                v = tremove(object, n)
            else
                v         = object[n]
                object[n] = tremove(object)
            end
        end
        return true, v
    end
    return false
end

local function shuffle(arr)
    local count = #arr
    while count > 1 do
        local n            = mrandom(1, count - 1)
        arr[count], arr[n] = arr[n], arr[count]
        count              = count - 1
    end
    return arr
end

local function contains(t, value)
    for _, v in pairs(t) do
        if (v == value) then
            return true
        end
    end
    return false
end

local function contains_if(t, fn)
    for k, v in pairs(t) do
        if fn(v) then
            return true
        end
    end
    return false
end

local function equals(a, b)
    for k, v in pairs(a) do
        if b[k] ~= v then
            return false
        end
    end
    for k, v in pairs(b) do
        if a[k] ~= v then
            return false
        end
    end
    return true
end

local function indexof(tbl, obj)
    for k, v in ipairs(tbl) do
        if v == obj then
            return k
        end
    end
end

local function findKeyByValue(tbl, obj)
    for k, v in pairs(tbl) do
        if v == obj then
            return k
        end
    end
end

---comment 过滤符合函数条件的元素并返回新的结果数组
---@param func   function  @回调函数, 返回值必须是`boolean`
---@param list   table     @原始数组
---@return table           @返回新数组
local function tfilter(func, list)
    local newlist = {}
    for i = 1, #list do
        if func(list[i]) then
            newlist[#newlist + 1] = list[i]
        end
    end
    return newlist
end

--反转table
local function treverse(arr)
    local tmp = {}
    for i = 1, #arr do
        local key = #arr + 1 - i
        tmp[i]    = arr[key]
    end
    return tmp
end

table_ext                   = _ENV.table_ext or {}

table_ext.random            = trandom
table_ext.random_array      = trandom_array
table_ext.indexof           = tindexof
table_ext.is_array          = tis_array
table_ext.size              = tsize
table_ext.copy              = tcopy
table_ext.deep_copy         = tdeep_copy
table_ext.delete            = tdelete
table_ext.join              = tjoin
table_ext.merge             = tmerge
table_ext.map               = tmap
table_ext.push              = tpush
table_ext.diff              = tdiff
table_ext.array             = tarray
table_ext.kvarray           = tkvarray
table_ext.mapsort           = tmapsort
table_ext.fastremove        = fastremove
table_ext.shuffle           = shuffle
table_ext.contains          = contains
table_ext.contains_if       = contains_if
table_ext.equals            = equals
table_ext.indexof           = indexof
table_ext.find_key_by_value = findKeyByValue
table_ext.filter            = tfilter
table_ext.reverse           = treverse

-- 按哈希key排序
--[[ 使用示例:
    for _, k, v spairs(t [, sortfunc]) do
        do_something()
    end
--]]
function table_ext.spairs(t, cmp)
    local sort_keys = {}
    for k, v in pairs(t) do
        sort_keys[#sort_keys + 1] = { k, v }
    end
    local sortfunc
    if cmp then
        sortfunc = function(a, b)
            return cmp(a[1], b[1])
        end
    else
        sortfunc = function(a, b)
            return a[1] < b[1]
        end
    end
    tsort(sort_keys, sortfunc)

    return function(tb, index)
        local ni, v = next(tb, index)
        if ni then
            return ni, v[1], v[2]
        else
            return ni
        end
    end, sort_keys, nil
end
