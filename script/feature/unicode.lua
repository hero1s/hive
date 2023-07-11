--unicode.lua

local type = type
local ssub = string.sub
local sbyte = string.byte
local schar = string.char
local sfind = string.find
local sformat = string.format
local tconcat = table.concat
local tonumber = tonumber

local Unicode = singleton()
function Unicode:__init()
end

function Unicode:encode(srcstr)
    if type(srcstr) ~= "string" then
        return srcstr
    end
    local i = 0
    local result = {}
    while true do
        i = i + 1
        local numbyte = sbyte(srcstr, i)
        if not numbyte then
            break
        end
        local value1, value2
        if numbyte >= 0x00 and numbyte <= 0x7f then
            value1 = numbyte
            value2 = 0
        elseif (numbyte & 0xe0) == 0xc0 then
            local t1 = (numbyte & 0x1f)
            i = i + 1
            local t2 = (sbyte(srcstr, i) & 0x3f)
            value1 = (t2 | ((t1 & 0x03) << 6))
            value2 = t1 >> 2
        elseif (numbyte & 0xf0) == 0xe0 then
            local t1 = (numbyte & 0x0f)
            i = i + 1
            local t2 = (sbyte(srcstr, i) & 0x3f)
            i = i + 1
            local t3 = (sbyte(srcstr, i) & 0x3f)
            value1 = (((t2 & 0x03) << 6) | t3)
            value2 = ((t1 << 4) | (t2 >> 2))
        else
            return nil, "out of range"
        end
        result[#result + 1] = sformat("\\u%02x%02x", value2, value1)
    end
    return tconcat(result)
end

function Unicode:decode(srcstr)
    if type(srcstr) ~= "string" then
        return srcstr
    end
    local i = 1
    local result = {}
    while true do
        local numbyte = sbyte(srcstr, i)
        if not numbyte then
            break
        end
        local substr = ssub(srcstr, i, i + 1)
        if substr == "\\u" then
            local unicode = tonumber("0x" .. ssub(srcstr, i + 2, i + 5))
            if not unicode then
                result[#result + 1] = substr
                i = i + 2
            else
                i = i + 6
                if unicode <= 0x007f then
                    -- 0xxxxxxx
                    result[#result + 1] = schar(unicode & 0x7f)
                elseif unicode >= 0x0080 and unicode <= 0x07ff then
                    -- 110xxxxx 10xxxxxx
                    result[#result + 1] = schar((0xc0 | ((unicode >> 6) & 0x1f)))
                    result[#result + 1] = schar((0x80 | (unicode & 0x3f)))
                elseif unicode >= 0x0800 and unicode <= 0xffff then
                    -- 1110xxxx 10xxxxxx 10xxxxxx
                    result[#result + 1] = schar((0xe0 | ((unicode >> 12) & 0x0f)))
                    result[#result + 1] = schar((0x80 | ((unicode >> 6) & 0x3f)))
                    result[#result + 1] = schar((0x80 | (unicode & 0x3f)))
                end
            end
        else
            result[#result + 1] = schar(numbyte)
            i = i + 1
        end
    end
    return tconcat(result)
end

--栈式字符串decode
function Unicode:sdecode(srcstr)
    if sfind(srcstr, "\\u") then
        return self:decode(srcstr)
    end
    local i = 0
    local fmtstr = ""
    while i + 4 <= #srcstr do
        fmtstr = sformat("%s\\u%s%s", fmtstr, ssub(srcstr, i + 3, i + 4), ssub(srcstr, i + 1, i + 2))
        i = i + 4
    end
    return self:decode(fmtstr)
end

hive.unicode = Unicode()

return Unicode
