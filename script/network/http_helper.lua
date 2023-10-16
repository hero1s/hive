local log_err  = logger.err
local pairs    = pairs
local tconcat  = table.concat
local tinsert  = table.insert
local sformat  = string.format
local sfind    = string.find
local ssub     = string.sub
local luencode = curl.url_encode
local tmapsort = table_ext.mapsort

http_helper    = {}

function http_helper.urlencoded(query, sort)
    if query and next(query) then
        local fquery = {}
        if sort then
            local params = tmapsort(query)
            for _, value in pairs(params) do
                local k, v = luencode(value[1]), luencode(value[2])
                if k and v then
                    fquery[#fquery + 1] = sformat("%s=%s", luencode(value[1]), luencode(value[2]))
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
