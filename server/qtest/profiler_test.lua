--profile_test.lua
import("feature/profile.lua")

local log_debug   = logger.debug
local lhex_encode = crypt.hex_encode
local guid_new    = codec.guid_new
local encode      = luakit.encode
local decode      = luakit.decode
local serialize   = luakit.serialize
local unserialize = luakit.unserialize

hive.profile(true)
--hive.perfwatch("qtest/profile_test.lua")
if hive.index == 1 then
    local m  = { f = 3 }
    local t  = {
        [3.63] = 1, 2, 3, 4,
        a      = 2,
        b      = {
            s = 3, d = "4"
        },
        e      = true,
        g      = m,
    }

    local ss = serialize(t)
    log_debug("serialize-> aaa: {}", ss)

    local tt = unserialize(ss)
    for k, v in pairs(tt) do
        log_debug("unserialize k={}, v={}", k, v)
    end

    --encode
    local e    = { a = 1, c = { ab = 2 } }
    local bufe = encode(e)
    log_debug("encode-> bufe: {}, {}", #bufe, lhex_encode(bufe))

    local datae = decode(bufe, #bufe)
    log_debug("decode-> {}", datae)

    for i = 1, 1000 do
        local ss1 = serialize(t)
        unserialize(ss1)
        local bufe1 = encode(e)
        decode(bufe1, #bufe1)

        guid_new(5, 512)
    end
end

if hive.index == 2 then
    local function test(a)
        timer.sleep(1000)
    end
    local function test2()
        log_debug("===============test2-1")
        coroutine.yield()
        test(3)
        log_debug("===============test2-2")
    end
    local function test1()
        log_debug("===============test1-1")
        local co = coroutine.create(test2)
        coroutine.resume(co)
        log_debug("===============test1-2")
        test(2)
        coroutine.resume(co)
        log_debug("===============test1-3")
    end

    local function prof()
        test(1)
        test1()
    end
    local t1 = timer.now_ms()
    prof()
    log_debug("prof-> {}", timer.now_ms() - t1)
end

hive.perfdump(10)


