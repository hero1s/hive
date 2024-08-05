local log_err    = logger.err
local pairs      = pairs
local tconcat    = table.concat
local tinsert    = table.insert
local sformat    = string.format
local sfind      = string.find
local ssub       = string.sub
local luencode   = curl.url_encode
local lmd5       = crypt.md5
local lb64encode = crypt.b64_encode
local lb64decode = crypt.b64_decode
local tmapsort   = table_ext.mapsort
local tmerge     = table_ext.merge
local mmin       = math.min

http_helper      = {}

local function cmp_key(a, b)
    local len = mmin(a[1]:len(), b[1]:len())
    for i = 1, len do
        local a1, b1 = a[1]:byte(i), b[1]:byte(i)
        if a1 ~= b1 then
            return a1 < b1
        end
    end
    return a[1]:len() < b[1]:len()
end

function http_helper.url_query_concat(query, sort)
    if query and next(query) then
        local fquery = {}
        if sort then
            local params = tmapsort(query, cmp_key)
            for _, value in pairs(params) do
                local k, v = value[1], value[2]
                if k and v then
                    fquery[#fquery + 1] = sformat("%s=%s", k, v)
                end
            end
        else
            for key, value in pairs(query) do
                fquery[#fquery + 1] = sformat("%s=%s", key, value)
            end
        end
        return tconcat(fquery, "&")
    end
    return ""
end

function http_helper.urlencoded(query, sort)
    if query and next(query) then
        local fquery = {}
        if sort then
            local params = tmapsort(query, cmp_key)
            for _, value in pairs(params) do
                local k, v = luencode(value[1]), luencode(value[2])
                if k and v then
                    fquery[#fquery + 1] = sformat("%s=%s", k, v)
                end
            end
        else
            for key, value in pairs(query) do
                fquery[#fquery + 1] = sformat("%s=%s", luencode(key), luencode(value))
            end
        end
        return tconcat(fquery, "&")
    end
    return ""
end

function http_helper.urldecoded(body)
    local body_table = {}
    local pos        = 1
    while true do
        local last_pos = pos
        pos            = sfind(body, '&', pos)
        if not pos then
            tinsert(body_table, ssub(body, last_pos))
            break
        end
        tinsert(body_table, ssub(body, last_pos, pos - 1))
        pos = pos + 1
    end
    local body_data = {}
    for _, body_row in ipairs(body_table) do
        local equal_pos = sfind(body_row, '=')
        if not equal_pos then
            break
        end
        body_data[ssub(body_row, 1, equal_pos - 1)] = ssub(body_row, equal_pos + 1)
    end
    return body_data
end

function http_helper.http_success(ok, code, res)
    if not ok or 200 ~= code then
        log_err("[http_failed] call failed:ok={},code={},res={},from:[{}]", ok, code, res, hive.where_call())
        return false
    end
    return true
end

--[[
securet:md5签名秘钥
headKeys:head里面需要校验的字段
1:Sign 字段为签名字段,Ts 为时间戳,放head
2:取出head 指定字段headKeys的参数以及get参数,存入map[string]string
3:对map的key排序后拼接字符串str += key + values
4:sign = md5(str + bodystr + securet + ts)
--]]

function http_helper.check_param(securet, headKeys, querys, body, head)
    local cli_sign = head["Sign"] or head["sign"]
    if not cli_sign then
        return false, "not exist sign param"
    end
    local ts     = head["Ts"] or head["ts"]
    local params = {}
    for _, v in pairs(headKeys) do
        params[v] = head[v]
    end
    tmerge(querys, params)
    params        = tmapsort(params, cmp_key)
    local cal_str = ""
    for _, value in pairs(params) do
        cal_str = cal_str .. value[1] .. value[2]
    end
    cal_str        = cal_str .. body .. securet .. ts
    local svr_sign = lmd5(cal_str, 1)
    if svr_sign ~= cli_sign then
        return false, sformat("%s,sign:%s --> cli:%s", cal_str, svr_sign, cli_sign)
    end
    return true
end

function http_helper.urlbase64_encode(str)
    local base64_str = lb64encode(str)
    return base64_str:gsub("/", "_"):gsub("+", "-"):gsub("=", "")
end

function http_helper.urlbase64_decode(str)
    local base64_str = str:gsub("_", "/"):gsub("-", "+")
    local padding    = #base64_str % 4
    if padding > 0 then
        base64_str = base64_str .. string.rep("=", 4 - padding)
    end
    return lb64decode(base64_str)
end


