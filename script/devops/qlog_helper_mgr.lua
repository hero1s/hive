--qlog_helper_mgr.lua
import("dlog_game/dlog_mgr.lua")

local otime      = os.time
local odate      = os.date
local PeriodTime = enum("PeriodTime")

local timer_mgr  = hive.get("timer_mgr")
local dlog_mgr   = hive.get("dlog_mgr")

local QlogHelperMgr  = singleton()
local prop = property(QlogHelperMgr)
prop:reader("ip", nil)

function QlogHelperMgr:__init()
    self.ip = hive.lan_ip

    timer_mgr:loop(PeriodTime.MINUTE_5_MS, function()
        self:on_5_minute()
    end)
end

function QlogHelperMgr:on_5_minute()
    local special_fields = {
        iZoneAreaID = 1,
        dtEventTime = odate("%Y-%m-%d %H:%M:%S", otime()),
        vGameIP     = self.ip,
        vGameName   = hive.name
    }
    dlog_mgr:send_dlog_game_svr_state({ special_fields = special_fields })
end

-- export
hive.qlog_helper_mgr = QlogHelperMgr()

return QlogHelperMgr
