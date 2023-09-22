--log_test.lua
require("lualog")

local ltimer    = require("ltimer")
local lnow_ms   = ltimer.now_ms
local log_info  = logger.info
local log_debug = logfeature.debug("lualog")

local json_str  = [[
{"openid":"o6FYl6OiHFKt6YqlYOtI2Jyn-Tfk","nickname":"炫喵","sex":0,"language":"","city":"","province":"","country":"","headimgurl":"@P�C\/132","privilege":[],"unionid":"o1A_Bjp2VuahI2yq27I0AVmC-2hE"}
]]

log_debug("begin:{}", json_str)

local ok, res = hive.try_json_decode(json_str, true)
log_debug("begin ok:{},res:{}", ok, res)

if string.find(json_str, "http") == nil then
    log_debug("success")
    local pos = string.find(json_str, "headimgurl")
    if pos then
        json_str = string.sub(json_str, 1, pos + 12) .. "\"}"
    end
    ok, res = hive.json_decode(json_str, true)
    log_debug("{},{}", ok, res)
else
    log_debug("failed")
end

log_debug("end:{}", json_str)

local tmp = { 1, 2, 3 }

for i = 1, 10 do
    table_ext.shuffle(tmp)
    log_debug("shuffle:{}", tmp)
end

local function test1()
    local _<close> = hive.defer(function()
        log_debug("defer call------------")
    end)
    local test2    = function()
        log_debug("return call------------")
    end
    return test2()
end

test1()

--os.exit()
