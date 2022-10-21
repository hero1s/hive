local lhelper = require("lhelper")

logger.debug("[%s] dns: [%s]", "www.baidu.com", lhelper.dns("www.baidu.com"))

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

logger.debug("ip:%s",guess_name_type("192.168.1.13"))
logger.debug("ip:%s",guess_name_type("192.168.1.13:jfdkalj"))
logger.debug("ip:%s",guess_name_type("baidu.com"))