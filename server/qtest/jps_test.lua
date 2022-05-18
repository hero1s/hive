local ljps      = require("ljps")
local lrandom   = require("lrandom")
local timer_mgr = hive.get("timer_mgr")

local map       = {}
--随机地图
local w,h = 100,100
for i = 1, w do
    for j = 1, h do
        local v = lrandom.rand_weight({0,1},{80,20})
        table.insert(map,v)
    end
end
--随机寻路点并设置非障碍
local sx,sy,ex,ey = lrandom.rand_range(1,10),lrandom.rand_range(1,10),lrandom.rand_range(80,99),lrandom.rand_range(80,99)
map[sx*h+sy] = 0
map[ex*h+ey] = 0

local ret       = ljps.init(w, h, map)
logger.debug("ljps init ret:%s", ret)
ljps.start()
ljps.request(998, sx, sy, ex, ey)
--ljps.debug(false)
timer_mgr:once(1000, function()
    local resps = ljps.response()
    logger.debug("resp count:%s",#resps)
    for _,resp in pairs(resps) do
        logger.debug("resp:%s,ret:%s,path:%s,cost time:%s",resp.session_id,resp.ret,#resp.path,resp.cost_time)
        for _,pos in pairs(resp.path) do
            logger.debug("{x:%s,y:%s}",pos.x,pos.y)
        end
    end
    ljps.stop()
end)
