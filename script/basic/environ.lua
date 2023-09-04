--environ.lua
local luabus    = require("luabus")

local tonumber  = tonumber
local ogetenv   = os.getenv
local tunpack   = table.unpack
local sgsub     = string.gsub
local sgmatch   = string.gmatch
local saddr     = string_ext.addr
local ssplit    = string_ext.split
local usplit    = string_ext.usplit
local protoaddr = string_ext.protoaddr

environ         = {}

local pattern   = "(%a+)://([^:]-):([^@]-)@([^/]+)/?([^?]*)[%?]?(.*)"

function environ.init()
    hive.lan_ip = luabus.lan_ip()
end

function environ.get(key, def)
    return ogetenv(key) or def
end

function environ.set(key, value)
    set_env(key, value)
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

local function parse_hosts(value)
    local hosts = {}
    local strs = ssplit(value, ",")
    for _, str in pairs(strs) do
        local k, v = saddr(str)
        if k then
            hosts[#hosts + 1] = { k, v }
        end
    end
    return hosts
end

local function parse_options(value)
    local opts = {}
    local strs = ssplit(value, "&")
    for _, str in pairs(strs) do
        local k, v = usplit(str, "=")
        if k and v then
            opts[k] = v
        end
    end
    return opts
end

local function parse_driver(value)
    local driver, usn, psd, hosts, db, opts = sgmatch(value, pattern)()
    if driver then
        return {
            db     = db, user = usn,
            passwd = psd, driver = driver,
            opts   = parse_options(opts),
            hosts  = parse_hosts(hosts)
        }
    end
end
--标准化url驱动配置
function environ.driver(url)
    if url then
        local drivers = {}
        local value1  = sgsub(url, " ", "")
        local value2  = sgsub(value1, "\n", "")
        local strs    = ssplit(value2, ";")
        for i, str in ipairs(strs) do
            drivers[i] = parse_driver(str)
        end
        return drivers
    end
end