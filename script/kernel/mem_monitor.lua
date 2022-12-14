local mri            = import("third/MemoryReferenceInfo.lua")
local tostring       = tostring
local pairs          = pairs
local tinsert        = table.insert
local tsort          = table.sort
local collectgarbage = collectgarbage
local log_debug      = logger.debug

local MemMonitor     = singleton()
local prop           = property(MemMonitor)
prop:reader("mtrack", {})

--构造函数
function MemMonitor:__init()
    mri.m_cConfig.m_bAllMemoryRefFileAddTime      = false
    mri.m_cConfig.m_bSingleMemoryRefFileAddTime   = false
    mri.m_cConfig.m_bComparedMemoryRefFileAddTime = false
    self.mtrack                                   = setmetatable({}, { __mode = "kv" })
end

function MemMonitor:start()
    collectgarbage("collect")
    mri.m_cMethods.DumpMemorySnapshot("./", "1-Before", -1)
end

function MemMonitor:stop(print)
    collectgarbage("collect")
    mri.m_cMethods.DumpMemorySnapshot("./", "2-After", -1)
    if print then
        self:print_diff()
    end
end

function MemMonitor:print_diff()
    mri.m_cMethods.DumpMemorySnapshotComparedFile("./", "Compared", -1, "./LuaMemRefInfo-All-[1-Before].txt", "./LuaMemRefInfo-All-[2-After].txt")
end

function MemMonitor:track(obj)
    self.mtrack[obj] = tostring(obj)
end

function MemMonitor:show_track(less_num)
    collectgarbage("collect")
    local m = {}
    for k, v in pairs(self.mtrack) do
        if not m[v] then
            m[v] = 0
        end
        m[v] = m[v] + 1
    end
    local l = {}
    for k, v in pairs(m) do
        if v >= less_num then
            tinsert(l, { k, v })
        end
    end
    tsort(l, function(a, b)
        return a[2] > b[2]
    end)
    log_debug("show track:%s", l)
    return l
end

hive.mem_monitor = MemMonitor()

return MemMonitor