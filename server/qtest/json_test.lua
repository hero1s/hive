--json_test.lua
local lcodec      = require("lcodec")
local ltimer      = require("ltimer")
local yyjson      = require("lyyjson")
local cjson       = require("lcjson")

local log_debug   = logger.debug
local new_guid    = lcodec.guid_new
local json_encode = cjson.encode
local json_decode = cjson.decode
local lencode     = lcodec.encode
local ldecode     = lcodec.decode
local lclock_ms   = ltimer.clock_ms

local func_list   = {
    ["cjson"]  = { json_encode, json_decode },
    ["yyjson"] = { yyjson.encode, yyjson.decode },
    ["lua"]    = { lencode, ldecode },
}

local test        = {
    tid       = 3.1415926,
    player_id = new_guid(hive.service_id, hive.index)
}

print(test.tid)
print(test.player_id)

local a = json_encode(test)
print(a)

local b = json_decode(a)
print(type(b.tid), b.tid)
print(type(b.player_id), b.player_id)

local function test_big(json_type, test_code)
    local str      = io_ext.readfile("./twitter.json")
    local jencode  = func_list[json_type][1]
    local jdecode  = func_list[json_type][2]
    local tmp      = jdecode(str)
    local clock_ms = lclock_ms()
    local count    = 1000
    for i = 1, count do
        if test_code == "decode" then
            jdecode(str)
        else
            jencode(tmp)
        end
    end
    local cost_ms = lclock_ms() - clock_ms
    log_debug("twitter %s[%s],count:%s cost_ms:%s,avg:%s", json_type, test_code, count, cost_ms, cost_ms / count)
end

local function test_small(json_type, test_code)
    local t        = {
        group_id      = 23432, friend_type = 1, player = {
            player_id     = 3232,
            nick          = "fdajlk",
            icon          = 23,
            sex           = 1,
            rank          = 234,
            status        = 12,
            team_id       = 32234214312,
            room_id       = 34143215411,
            time          = hive.now,
            online_status = 1,
            stars         = 1232,
            win_games     = 123,
            mvp_count     = 3142,
            total_games   = 452354,
            avr_kill      = 435,
            freq_roles    = { 12, 1234, 345, 4352 },
            level         = 423,
            room_status   = 2,
            game_mode     = 2,
            logout_time   = hive.now,
            settings      = { 1, 2, 3, 4, 5, 5 }
        }, intimacy   = 4325,
        remarks       = "434321uofjadslk",
        social_secret = 2,
        friend_time   = hive.now
    }
    local jencode  = func_list[json_type][1]
    local jdecode  = func_list[json_type][2]
    local str      = jencode(t)
    local clock_ms = lclock_ms()
    local count    = 10000
    for i = 1, count do
        if test_code == "decode" then
            jdecode(str)
        else
            jencode(t)
        end
    end
    local cost_ms = lclock_ms() - clock_ms
    log_debug("small   %s[%s],count:%s cost_ms:%s,avg:%s", json_type, test_code, count, cost_ms, cost_ms / count)
end
local test_type = "yyjson"
test_big(test_type, "decode")
test_big(test_type, "encode")
test_small(test_type, "decode")
test_small(test_type, "encode")

test_type = "cjson"
test_big(test_type, "decode")
test_big(test_type, "encode")
test_small(test_type, "decode")
test_small(test_type, "encode")

test_type = "lua"
--test_big(test_type, "decode")
--test_big(test_type, "encode")
--test_small(test_type, "decode")
test_small(test_type, "encode")
