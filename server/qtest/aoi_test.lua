local lrandom = require("lrandom")
local aoi = import("utility/aoi.lua")

local w = -256
local h = -256

local scene = aoi(w,h,512)

for i = 1, 10 do
    scene:insert(i,lrandom.rand_range(w,1),lrandom.rand_range(h,1),200,1)
end

for i = 1, 10 do
    scene:update(i,lrandom.rand_range(w,1),lrandom.rand_range(h,1),200)
end

for i = 1, 10 do
    scene:query(lrandom.rand_range(w,1),lrandom.rand_range(h,1),200,200)
end

for i = 1, 10 do
    scene:erase(i)
end


