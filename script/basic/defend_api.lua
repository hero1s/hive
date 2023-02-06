local ljson      = require("lyyjson")
local xpcall_ret = hive.xpcall_ret

function hive.json_decode(json_str, result)
    local ok, res = xpcall_ret(ljson.decode, "[hive.json_decode] error:%s", json_str)
    if not ok then
        logger.err("[hive][json_decode] err json_str:[%s]", json_str)
    end
    if result then
        return ok, ok and res or nil
    else
        return ok and res or nil
    end
end

function hive.json_encode(body)
    local ok, jstr = xpcall_ret(ljson.encode, "[hive.json_encode] error:%s", body)
    if not ok then
        logger.err("[hive][json_encode] err body:[%s]", body)
    end
    return ok and jstr or ""
end