local lcurl    = require("lcurl")

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

