--json_test.lua
local lcrypt      = require("lcrypt")

local new_guid    = lcrypt.guid_new
local json_encode = hive.json_encode
local json_decode = hive.json_decode

local test        = {
    tid       = 3.1415926,
    player_id = new_guid()
}

print(test.tid)
print(test.player_id)

local a = json_encode(test)
print(a)

local b = json_decode(a)
print(type(b.tid), b.tid)
print(type(b.player_id), b.player_id)

os.exit()
