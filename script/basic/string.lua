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
    local t = {}
    while #str > 0 do
        local pos = sfind(str, token)
        if not pos then
            t[#t + 1] = str
            break
        end
        if pos > 1 then
            t[#t + 1] = ssub(str, 1, pos - 1)
        end
        str = ssub(str, pos + 1, #str)
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




