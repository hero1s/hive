local lhelper = require("lhelper")

logger.debug("mem_available:{}", lhelper.mem_available())
logger.debug("cpu_use_percent:{}", lhelper.cpu_use_percent())
logger.debug("cpu_core_num:{}", lhelper.cpu_core_num())
logger.debug("mem_usage:{}", lhelper.mem_usage())

logger.debug("[{}] dns: [{}]", "www.baidu.com", luabus.dns("www.baidu.com"))

-- return name type: 'ipv4', 'ipv6', or 'hostname'
local function guess_name_type(name)
    if name:match("^[%d%.]+$") then
        return "ipv4"
    end
    if name:find(":") then
        return "ipv6"
    end
    return "hostname"
end

logger.debug("ip:{}", guess_name_type("192.168.1.13"))
logger.debug("ip:{}", guess_name_type("192.168.1.13:jfdkalj"))
logger.debug("ip:{}", guess_name_type("baidu.com"))
logger.debug("ip:{}", guess_name_type("git.ids111.com"))

local udp     = luabus.udp()
local ok, err = udp.listen("0.0.0.0", 8080)
logger.debug("ok:{},err:{}", ok, err)

logger.debug("lan ip:{},udp port:8080:{},port:20013:tcp[{}],udp:[{}]",
        luabus.host(), luabus.port_is_used(8080, false), luabus.port_is_used(20013, true), luabus.port_is_used(20013, false))
