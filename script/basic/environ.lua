--environ.lua
local pairs     = pairs
local tonumber  = tonumber
local log_info  = logger.info
local tunpack   = table.unpack
local hgetenv   = hive.getenv
local tmapsort  = table_ext.mapsort
local saddr     = string_ext.addr
local ssplit    = string_ext.split
local protoaddr = string_ext.protoaddr

environ         = {}

--环境变量表
local HIVE_ENV  = hive.environs

function environ.init()
    local env_file = hgetenv("HIVE_ENV")
    if env_file then
        --exp: --env=env/router
        local custom     = require(env_file)
        local index      = environ.number("HIVE_INDEX", 1)
        local custom_env = custom and custom[index]
        for key, value in pairs(custom_env or {}) do
            HIVE_ENV[key] = value
        end
    end
    log_info("---------------------environ value dump-------------------")
    local sort_envs = tmapsort(HIVE_ENV)
    for _, env_pair in pairs(sort_envs) do
        log_info("%s ----> %s", env_pair[1], env_pair[2])
    end
    log_info("----------------------------------------------------------")
end

function environ.get(key, def)
    return HIVE_ENV[key] or hgetenv(key) or def
end

function environ.number(key, def)
    return tonumber(HIVE_ENV[key] or hgetenv(key) or def)
end

function environ.status(key)
    return (tonumber(HIVE_ENV[key] or hgetenv(key) or 0) > 0)
end

function environ.addr(key)
    local value = HIVE_ENV[key] or hgetenv(key)
    if value then
        return saddr(value)
    end
end

function environ.protoaddr(key)
    local value = HIVE_ENV[key] or hgetenv(key)
    if value then
        return protoaddr(value)
    end
end

function environ.split(key, val)
    local value = HIVE_ENV[key] or hgetenv(key)
    if value then
        return tunpack(ssplit(value, val))
    end
end

function environ.table(key, str)
    return ssplit(HIVE_ENV[key] or hgetenv(key) or "", str or ",")
end
