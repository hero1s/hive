--serialize.lua

local lbuffer   = require("lbuffer")
local serializer= lbuffer.new_serializer()

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
