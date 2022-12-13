local mem_monitor        = hive.get("mem_monitor")
mem_monitor:start()

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

local author =
{
    Name = "yaukeywang",
    Job = "Game Developer",
    Hobby = "Game, Travel, Gym",
    City = "Beijing",
    Country = "China",
    Ask = function (question)
        return "My answer is for your question: " .. question .. "."
    end
}

_G.Author = author


mem_monitor:stop(true)


