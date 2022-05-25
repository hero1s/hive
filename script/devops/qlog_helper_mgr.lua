--qlog_helper_mgr.lua
import("tlog_game/tlog_mgr.lua")

local otime      = os.time
local odate      = os.date
local PeriodTime = enum("PeriodTime")

local timer_mgr  = hive.get("timer_mgr")
local tlog_mgr   = hive.get("tlog_mgr")

local TlogHelperMgr  = singleton()
local prop = property(TlogHelperMgr)
prop:reader("ip", nil)

function TlogHelperMgr:__init()
    self.ip = hive.lan_ip

    timer_mgr:loop(PeriodTime.MINUTE_5_MS, function()
        self:on_5_minute()
    end)
end

function TlogHelperMgr:on_5_minute()
    local special_fields = {
        ZoneID      = 1,
        dtEventTime = odate("%Y-%m-%d %H:%M:%S", otime()),
        GameIP      = self.ip,
        GameName    = hive.name
    }
    tlog_mgr:send_tlog_game_svr_state({ special_fields = special_fields })
end

-- export
hive.tlog_helper_mgr = TlogHelperMgr()

return TlogHelperMgr
