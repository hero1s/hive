--log_test.lua
require("lualog")

local ltimer    = require("ltimer")
local lnow_ms   = ltimer.now_ms
local log_info  = logger.info
local log_debug = logfeature.debug("lualog")

local json_str  = [[
{"openid":"o6FYl6OiHFKt6YqlYOtI2Jyn-Tfk","nickname":"炫喵","sex":0,"language":"","city":"","province":"","country":"","headimgurl":"@P�C\/132","privilege":[],"unionid":"o1A_Bjp2VuahI2yq27I0AVmC-2hE"}
]]

log_debug("begin:%s", json_str)

local ok, res = hive.try_json_decode(json_str, true)
log_debug("begin ok:%s,res:%s",ok,res)

if string.find(json_str, "http") == nil then
    log_debug("success")
    local pos = string.find(json_str, "headimgurl")
    if pos then
        json_str = string.sub(json_str, 1, pos + 12) .. "\"}"
    end
    ok, res = hive.json_decode(json_str, true)
    log_debug("%s,%s", ok, res)
else
    log_debug("failed")
end

log_debug("end:%s", json_str)

--os.exit()
