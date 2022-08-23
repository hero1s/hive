local snapshot = import("utility/snapshot.lua")

local S        = snapshot()
S:start()

local tmp = {
    player  = {
        uid   = 1,
        camps = {
            { campid = 1 },
            { campid = 2 },
        },
    },
    player2 = {
        roleid = 2,
    },
    [3]     = {
        player1 = 1,
    },
}

local a   = {}
local c   = {}
a.b       = c
c.d       = a

local msg = "bar"
local foo = function()
    print(msg)
end

local co  = coroutine.create(function()
    print("hello world")
end)

S:stop()
S:print_diff()

