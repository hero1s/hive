--serialize.lua
local ljson      = require("lcjson")
local lbuffer    = require("lbuffer")
local serializer = lbuffer.new_serializer()

local pcall      = pcall

function hive.encode(...)
    return serializer.encode(...)
end

function hive.decode(slice)
    return serializer.decode(slice)
end

function hive.encode_string(...)
    return serializer.encode_string(...)
end

function hive.decode_string(data, len)
    return serializer.decode_string(data, len)
end

function hive.serialize(tab, line)
    return serializer.serialize(tab, line)
end

function hive.unserialize(str)
    return serializer.unserialize(str)
end

function hive.json_decode(json_str, result)
    local ok, res = pcall(ljson.decode, json_str)
    if not ok then
        logger.err("[hive.json_decode] json_str:%s,error:%s", json_str, res)
    end
    if result then
        return ok, res
    else
        return res
    end
end

function hive.json_encode(body)
    local ok, jstr = pcall(ljson.encode, body)
    if not ok then
        logger.err("[hive.json_encode] body:%s,error:%s", body, jstr)
        return ""
    end
    return jstr
end