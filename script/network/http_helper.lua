local lcurl    = require("lcurl")
local log_err  = logger.err
local pairs    = pairs
local tconcat  = table.concat
local sformat  = string.format
local luencode = lcurl.url_encode
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

function http_helper.http_success(ok, code, res)
    if not ok or 200 ~= code then
        log_err("[http_failed] call failed:ok=%s,code=%s,res=%s,from:[%s]", ok, code, res, hive.where_call())
        return false
    end
    return true
end
