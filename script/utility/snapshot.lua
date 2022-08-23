-- snapshot
local lsnapshot = require("lsnapshot")
local log_debug = logger.debug
local log_dump  = logger.dump
local SnapShot  = class()
local prop      = property(SnapShot)
prop:reader("begin_s", nil)
prop:reader("end_s", nil)
prop:reader("diff", {})

--构造函数
function SnapShot:__init()

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
            self.diff[k] = v
        end
    end
    log_dump("diff:%s", self.diff)
end

return SnapShot