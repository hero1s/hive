--protobuf_test.lua

local protobuf  = require("driver.protobuf")
local pb_decode = protobuf.decode
local pb_encode = protobuf.encode

local pb_data   = {
    level     = 80,
    level1    = 801,
    talent_id = 5000
}

local pb_str    = pb_encode("common.player_talent_info", pb_data)
local data      = pb_decode("common.player_talent_info", pb_str)

print("talent_id", data.talent_id)
print("level", data.level)
print("level", data.level1)

os.exit()
