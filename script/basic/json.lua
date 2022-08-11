local ljson      = require("lcjson")

local xpcall_ret = hive.xpcall_ret

function hive.json_decode(json_str, result)
    local ok, res = xpcall_ret(ljson.decode, "[hive.json_decode] error:%s", json_str)
    if result then
        return ok, ok and res or nil
    else
        return ok and res or nil
    end
end

function hive.json_encode(body)
    local ok, jstr = xpcall_ret(ljson.encode, "[hive.json_encode] error:%s", body)
    return ok and jstr or ""
end