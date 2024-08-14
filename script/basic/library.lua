--library.lua
local hgetenv = hive.getenv

--约定逻辑层不修改全局变量

--日志库
log           = require("lualog")
--文件系统库
stdfs         = require("lstdfs")
--定时器库
timer         = require("ltimer")
--PB解析库
protobuf      = require("luapb")
--json库
json          = require("ljson")
--bson库
bson          = require("bson")
--编码库
codec         = require("lcodec")
--加密解密库
crypt         = require("lcrypt")
--网络库
luabus        = require("luabus")
--cache库
lcache        = require("lcache")

--特定模块
if hgetenv("HIVE_SERVICE") then
    --Curl库
    curl = require("lcurl")
end


