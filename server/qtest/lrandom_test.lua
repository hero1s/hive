local random = require("lrandom")
local log_debug = logger.debug

for i = 1, 10 do
    -------------------------[min,max]
    log_debug("rand_range:%i:%s", i, random.rand_range(1, 10))
end

for i = 1, 10 do
    -------------------------[min,max]
    log_debug("rand_range_some:%i:%s",i, random.rand_range_some(1, 10, 2))
end

log_debug("rand_range_some[1-100]:%s", random.rand_range_some(1, 100, 10))

local res = {}
for i = 1, 10000 do
    local v = random.rand_weight({ 1, 2, 3, 4, 5 }, { 100, 200, 300, 400, 500 })
    if res[v] then
        res[v] = res[v] + 1
    else
        res[v] = 1
    end
end

log_debug("rand_weight:%s", res)

res = {}
for i = 1, 10000 do
    local vv = random.rand_weight_some({ 1, 2, 3, 4, 5 }, { 100, 200, 300, 400, 500 }, 5)
    for _, v in ipairs(vv) do
        if res[v] then
            res[v] = res[v] + 1
        else
            res[v] = 1
        end
    end
end

log_debug("rand_weight_some:%s", res)

res = {}
for i = 1, 100000 do
    local v = random.rand_weight({ 1, 2 }, { 100, 100 })
    if res[v] then
        res[v] = res[v] + 1
    else
        res[v] = 1
    end
end

log_debug("rand_weight:%s", res)

log_debug("%s", (res[1] / 100000 - res[2] / 100000))
assert(math.abs(res[1] / 100000 - res[2] / 100000) < 0.01)

local succcount = 0
for i = 1, 100000 do
    if random.randf_percent(0.8) then
        succcount = succcount + 1
    end
end

log_debug("randf_percent:%s", succcount / 100000)
