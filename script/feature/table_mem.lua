local lencode    = luakit.encode
local log_dump   = logger.dump
local xpcall_ret = hive.xpcall_ret

local TableMem   = class()
local prop       = property(TableMem)
prop:reader("name", "")
prop:reader("max_depth", 3)
prop:reader("less_size", 10)
function TableMem:__init(max_depth, less_size)
    self.max_depth = max_depth or 3
    self.less_size = less_size or 10
end

function TableMem:table_size_dump(src, name)
    local ndst = self:table_map_size(src)
    log_dump("table_size [%s]-> %s", name or "", ndst)
end

function TableMem:table_map_size(src, dst, depth)
    local ndst = dst or {}
    depth      = depth or 1
    if depth > self.max_depth then
        return ndst
    end
    for field, value in pairs(src) do
        if type(value) == "table" then
            local len = self:table_size(value)
            if len > self.less_size then
                ndst[field] = { len = len }
                self:table_map_size(value, ndst[field], depth + 1)
            end
            if len == 0 then
                ndst[field] = { "more than max depth" }
            end
        end
    end
    return ndst
end

function TableMem:table_size(value)
    local ok, buff = xpcall_ret(lencode, nil, value)
    return ok and #buff or 0
end

return TableMem