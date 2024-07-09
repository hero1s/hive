--string.lua
local type     = type
local load     = load
local pcall    = pcall
local tostring = tostring
local tonumber = tonumber
local tunpack  = table.unpack
local tinsert  = table.insert
local ssub     = string.sub
local sfind    = string.find
local supper   = string.upper
local slower   = string.lower
local sformat  = string.format
local sbyte    = string.byte

string_ext     = _ENV.string_ext or {}

--------------------------------------------------------------------------------
function string_ext.eval(str)
    if str == nil then
        str = tostring(str)
    elseif type(str) ~= "string" then
        return {}
    elseif #str == 0 then
        return {}
    end
    local code, ret = pcall(load(sformat("do local _=%s return _ end", str)))
    return code and ret or {}
end
--首字母大写
function string_ext.title(value)
    return supper(ssub(value, 1, 1)) .. ssub(value, 2, #value)
end
--首字母小写
function string_ext.untitle(value)
    return slower(ssub(value, 1, 1)) .. ssub(value, 2, #value)
end

--切分字符串
function string_ext.split(str, token)
    local pos, t = 0, {}
    if #str > 0 then
        for st, sp in function()
            return sfind(str, token, pos, true)
        end do
            if st > 1 then
                t[#t + 1] = ssub(str, pos, st - 1)
            end
            pos = sp + 1
        end
        if pos <= #str then
            t[#t + 1] = ssub(str, pos)
        end
    end
    return t
end

function string_ext.split_ext(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(str, from, delim_from - 1))
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end
    table.insert(result, string.sub(str, from))
    return result
end

function string_ext.split_pos(str, token)
    if #str > 0 then
        local elem   = {}
        local pos, t = 0, { cur = 0 }
        for st, sp in function()
            return sfind(str, token, pos, true)
        end do
            if st > 1 then
                elem[#elem + 1] = { ssub(str, pos, st - 1), sp }
            end
            pos = sp + 1
        end
        if pos <= #str then
            elem[#elem + 1] = { ssub(str, pos), #str }
        end
        t.elem = elem
        return t
    end
end

--判断结尾
function string_ext.ends_with(str, ending)
    return str:sub(-#ending) == ending
end
--辅助接口
--------------------------------------------------------------------------------
local ssplit = string_ext.split
function string_ext.addr(value)
    local ip, port = tunpack(ssplit(value, ":"))
    return ip, tonumber(port)
end

function string_ext.protoaddr(value)
    local addr, proto = tunpack(ssplit(value, "/"))
    if addr then
        local ip, port = tunpack(ssplit(addr, ":"))
        return ip, tonumber(port), proto
    end
end

--移除首尾空格
function string_ext.trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

function string_ext.usplit(str, token)
    return tunpack(ssplit(str, token))
end

function string_ext.count(value, chl)
    local c, p = 0, 0
    while true do
        p = sfind(value, chl, p + 1, 0)
        if not p then
            break
        end
        c = c + 1
    end
    return c
end

function string_ext.chars(src)
    local chars  = {}
    local scount = 0 --单字节
    if not src then
        return chars, scount
    end
    local pos_bytes = 1
    while pos_bytes <= #src do
        local byteCount
        local curByte = sbyte(src, pos_bytes)
        -- [0x00, 0x7f] [0x80, 0x7ff] [0x800, 0xd7ff] [0x10000, 0x10ffff]
        if curByte < 128 then
            byteCount = 1  -- 单字节字符
            scount    = scount + 1
        elseif curByte < 222 then
            byteCount = 2  -- 双字节字符
        elseif curByte < 238 then
            byteCount = 3  -- 汉字
        else
            byteCount = 4  -- 4字节字符
        end
        tinsert(chars, ssub(src, pos_bytes, pos_bytes + byteCount - 1))
        pos_bytes = pos_bytes + byteCount
    end
    return chars, scount
end

-- 获取字符串中的字符数量(汉字字母都算一个)
function string_ext.get_char_len(src)
    local chars = string_ext.chars(src)
    return #chars
end


-- 正则转义字符集
--[[
%a	字母a-z,A-Z
%b	%bxy,以x和y进行成对匹配
%c	控制字符ASCII码 十进制转义表示为\0 - \31
%d	数字 0 - 9
%f	%f[char-set]，边界匹配，前一个不在范围内，后一个在
%g	除了空格以外的可打印字符 十进制转义表示为\33 - \126
%l	小写字母 a - z
%u	大写字母 A - Z
%s	空格 十进制转义表示为\32
%p	标点符号，即!@#$%^&*()`~-_=+{}:"<>?[];',./| 32个字符
%w	字母数字 a - z, A - Z, 0 - 9
%x	十六进制符号 0 - 9, a - f, A - F
--]]

-- 是否正则匹配成功
function string_ext.is_regular_match(string, pattern)
    return string.match(string, pattern)
end