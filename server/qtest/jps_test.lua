local ljps   = require("ljps")
local random = require("lrandom")

local map    = {}
--随机地图
local w, h   = 50, 50
for i = 1, w do
    for j = 1, h do
        local v = random.rand_weight({ 0, 1 }, { 80, 20 })
        table.insert(map, v)
    end
end
--随机寻路点并设置非障碍
local sx, sy, ex, ey = random.rand_range(1, 10), random.rand_range(1, 10), random.rand_range(40, 49), random.rand_range(40, 49)
map[sx * h + sy]     = 0
map[ex * h + ey]     = 0
local mapdata        = ""
for i, v in ipairs(map) do
    mapdata = mapdata .. v
end

local jps = ljps.new()
--jps.enable_debug(false)
local ret = jps.init(w, h, mapdata)
logger.debug("ljps init ret:%s", ret)

local result = jps.find_path(sx, sy, ex, ey)

logger.debug("%s,%s -->%s,%s result:%s", sx, sy, ex, ey, result)
