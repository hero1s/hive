local c = require("lprofiler")
c.init()
local mark          = c.mark

local M             = {
    start = c.start,
    stop  = c.stop,
}

local old_co_create = coroutine.create
local old_co_wrap   = coroutine.wrap

function coroutine.create(f)
    return old_co_create(function(...)
        mark()
        return f(...)
    end)
end

function coroutine.wrap(f)
    return old_co_wrap(function(...)
        mark()
        return f(...)
    end)
end

function M.dump(records)
    local ret = { "------- dump profile -------" }
    for i, v in ipairs(records) do
        local s       = string.format("[%d] %s name:%s file:[%s]%s:%d count:%d total:%fs ave:%fs percent:%.4g%%",
                i, v.point, v.name, v.flag, v.source, v.line, v.count, v.all_cost, v.ave_cost, v.percent * 100)
        ret[#ret + 1] = s
    end
    return table.concat(ret, "\n")
end

function M.dstop(count)
    local records = c.stop(count)
    local s       = M.dump(records)
    logger.info("%s", s)
end

return M
