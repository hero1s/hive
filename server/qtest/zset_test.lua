do
    local zset = require("lzset")
    local max_rank = 3
    local rank = zset.new(max_rank,2,"><")
    rank:update(4, 1, 4)
    rank:update(3, 2, 3)
    rank:update(2, 3, 2)
    rank:update(1, 4, 1)
    assert(rank:rank(1) == 1)
    assert(rank:rank(2) == 2)
    assert(rank:rank(3) == 3)
    assert(rank:rank(4) == 0)
    assert(rank:size() == 3)
    local rsize = rank:size()
    for i = 1, rsize do
        logger.debug("rank:%s,%s",i,rank:rank(i))
    end

    local res = rank:range(1, 4)
    assert(#res == 3)
    local top4 = rank:range(1, 4)
    logger.dump("top4:%s", top4)
    local r = rank:rank(2)
    local score = rank:score(2)
    logger.debug("2 rank:%s,score:%s",r,score)
    rank:clear()
    assert(not rank:range(1, 4))
    logger.debug("zset test finish")
end