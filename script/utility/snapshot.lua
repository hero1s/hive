-- snapshot
local lsnapshot = require("lsnapshot")
local tostring  = tostring
local pairs     = pairs
local tinsert   = table.insert
local tsort     = table.sort

local log_debug = logger.debug
local log_dump  = logger.dump
local SnapShot  = class()
local prop      = property(SnapShot)
prop:reader("begin_s", nil)
prop:reader("end_s", nil)
prop:reader("diff", {})

--构造函数
function SnapShot:__init()
    self.mtrack = setmetatable({}, { __mode = "kv" })
end

function SnapShot:start()
    self.begin_s = lsnapshot()
end

function SnapShot:stop()
    self.end_s = lsnapshot()
end

function SnapShot:print_diff()
    if not self.begin_s or not self.end_s then
        log_debug("[SnapShot][diff] the snapshot is nil")
        return
    end
    for k, v in pairs(self.end_s) do
        if not self.begin_s[k] then
            self.diff[tostring(k)] = tostring(v)
        end
    end
    log_dump("diff:%s", self.diff)
end

function SnapShot:track(obj)
    if is_class(obj) then
        local key        = obj:tostring()
        self.mtrack[obj] = key
    end
end

function SnapShot:show_track()
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
        tinsert(l, { k, v })
    end
    tsort(l, function(a, b)
        return a[2] > b[2]
    end)
    return l
end

return SnapShot