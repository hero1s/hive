local lprofiler    = require("lprofiler")
local lcodec       = require("lcodec")
local lcrypt       = require("lcrypt")

local log_debug    = logger.debug
local log_dump     = logger.dump
local lhex_encode  = lcrypt.hex_encode
local lencode      = lcodec.encode
local ldecode      = lcodec.decode
local lserialize   = lcodec.serialize
local lunserialize = lcodec.unserialize

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

thread_mgr:fork(function()
    lprofiler.start("lserialize")
    local ss = lserialize(t)
    lprofiler.stop("lserialize")
    log_debug("serialize-> aaa: %s", ss)
    lprofiler.start("lunserialize")
    local tt = lunserialize(ss)
    for k, v in pairs(tt) do
        log_debug("unserialize k=%s, v=%s", k, v)
    end

    lprofiler.start("lencode")
    local es = lencode(a)
    log_debug("encode-> aa: %d, %s", #es, lhex_encode(es))
    lprofiler.stop("lencode")

    for i = 1, 10 do
        log_debug("next_id1-> %d", lcodec.next_id(1))
        log_debug("next_id2-> %d", lcodec.next_id(2))
    end

    thread_mgr:sleep(2000)
    lprofiler.stop("lunserialize")
    log_dump("\t\n %s", lprofiler.info())

end)

--dump
log_dump("dump-> a: %s", t)



