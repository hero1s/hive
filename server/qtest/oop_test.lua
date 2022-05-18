--oop_test.lua

local Object = class(nil, IObject)
local prop2  = property(Object)
prop2:accessor("key3", 3)
function Object:__init()
end

function Object:__release()
    print("release", self)
end

function Object:run()
    print("key3", self:get_key3())
    print("key1", self:get_key1())
    print("key2", self:get_key2())
    self:invoke("test1")
end

local TEST1 = enum("TEST1", 0, "ONE", "THREE", "TWO")
print(TEST1.TWO)
local TEST2 = enum("TEST2", 1, "ONE", "THREE", "TWO")
TEST2.FOUR  = TEST2()
print(TEST2.TWO, TEST2.FOUR)
local TEST3 = enum("TEST3", 0)
TEST3("ONE")
TEST3("TWO")
TEST3("FOUR", 4)
local five = TEST3("FIVE")
print(TEST3.TWO, TEST3.FOUR, TEST3.FIVE, five)

local obj = Object()
obj:run()

return Object
