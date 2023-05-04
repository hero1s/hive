--string.lua
local type     = type
local load     = load
local pcall    = pcall
local tostring = tostring
local tonumber = tonumber
local tunpack  = table.unpack
local ssub     = string.sub
local sfind    = string.find
local supper   = string.upper
local slower   = string.lower
local sformat  = string.format

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
        for st, sp in function() return sfind(str, token, pos, true) end do
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

function string_ext.split_pos(str, token)
    local pos, t = 0, { cur = 0 }
    if #str > 0 then
        local elem = {}
        for st, sp in function() return sfind(str, token, pos, true) end do
            if st > 1 then
                elem[#elem + 1] = {ssub(str, pos, st - 1), sp }
            end
            pos = sp + 1
        end
        if pos <= #str then
            elem[#elem + 1] = { ssub(str, pos), #str }
        end
        t.elem = elem
    end
    return t
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

--移除首位空格
function string_ext.trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

function string_ext.usplit(str, token)
    return tunpack(ssplit(str, token))
end




