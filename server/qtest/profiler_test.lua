local profile      = import("utility/profile.lua")
local lcodec       = require("lcodec")
local lcrypt       = require("lcrypt")

local log_debug    = logger.debug
local log_dump     = logger.dump
local lhex_encode  = lcrypt.hex_encode
local lencode      = luakit.encode
local ldecode      = luakit.decode
local lserialize   = luakit.serialize
local lunserialize = luakit.unserialize

local timer_mgr    = hive.get("timer_mgr")
local thread_mgr   = hive.get("thread_mgr")

--serialize
----------------------------------------------------------------
local m            = { f = 3 }
local t            = {
    [3.63] = 1, 2, 3, 4,
    a      = 2,
    b      = {
        s = 3, d = "4"
    },
    e      = true,
    g      = m,
}

local a            = { a = 1, c = { a = 2 } }
profile.start()
thread_mgr:fork(function()
    for i = 1, 10 do
        log_debug("next_id1-> %d", lcodec.next_id(1))
        log_debug("next_id2-> %d", lcodec.next_id(2))
    end
    for i = 0, 1000 do
        lcodec.next_id(1)
        lcodec.next_id(2)
        local aa = json.encode(a)
        json.decode(aa)
        local ss = lserialize(a)
        local tt = lunserialize(ss)
    end
    thread_mgr:sleep(2000)
end)

--dump
profile.dstop(10)



