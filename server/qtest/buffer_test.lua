--buffer_test.lua
local lcodec       = require("lcodec")
local lcrypt       = require("lcrypt")

local log_debug    = logger.debug
local log_dump     = logger.dump
local lhex_encode  = lcrypt.hex_encode
local lencode      = luakit.encode
local ldecode      = luakit.decode
local lserialize   = luakit.serialize
local lunserialize = luakit.unserialize

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

local ss           = lserialize(t)
log_debug("serialize-> aaa: {}", ss)
local tt = lunserialize(ss)
for k, v in pairs(tt) do
    log_debug("unserialize k={}, v={}", k, v)
end

--encode
local a  = { a = 1, c = { a = 2 } }
local es = lencode(a)
log_debug("encode-> aa: {}, {}", #es, lhex_encode(es))
local da = ldecode(es)
log_debug("decode-> {}", da)

--dump
log_dump("dump-> a: {}", t)