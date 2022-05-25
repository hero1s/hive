--environ.lua
local lhelper = require("lhelper")

local tonumber  = tonumber
local ogetenv   = os.getenv
local tunpack   = table.unpack
local saddr     = string_ext.addr
local ssplit    = string_ext.split
local protoaddr = string_ext.protoaddr

environ = {}

function environ.init()
    hive.mode = environ.number("HIVE_MODE", 1)
    hive.lan_ip = lhelper.get_lan_ip()
end

function environ.get(key, def)
    return ogetenv(key) or def
end

function environ.number(key, def)
    return tonumber(ogetenv(key) or def)
end

function environ.status(key)
    return (tonumber(ogetenv(key) or 0) > 0)
end

function environ.addr(key)
    local value = ogetenv(key)
    if value then
        return saddr(value)
    end
end

function environ.protoaddr(key)
    local value = ogetenv(key)
    if value then
        return protoaddr(value)
    end
end

function environ.split(key, val)
    local value = ogetenv(key)
    if value then
        return tunpack(ssplit(value, val))
    end
end

function environ.table(key, str)
    return ssplit(ogetenv(key) or "", str or ",")
end
