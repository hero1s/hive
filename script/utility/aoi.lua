-- aoi
local laoi         = require("laoi")
local mfloor      = math.floor
local mceil       = math.ceil
local log_debug   = logger.debug

local AOI_WATCHER = 1  --观察者
local AOI_MARHER  = 2  --被观察者
local EVENT_ENTER = 1
local EVENT_LEAVE = 2

local AoiModel    = class()
local prop        = property(AoiModel)
prop:reader("space", nil)
prop:reader("event_cache", {})

--构造函数
function AoiModel:__init(orginx, orginy, size)
    self.space = laoi.create(orginx, orginy, size, 16)
    self.space:enable_leave_event(true)
end

function AoiModel:__release()
    laoi.release(self.space)
end

function AoiModel:enable_debug(enable)
    self.space:enable_debug(enable)
end

function AoiModel:enable_leave_event(enable)
    self.space:enable_leave_event(enable)
end

function AoiModel:insert(id, x, y, view_size, mover)
    if mover then
        self.space:insert(id, x, y, view_size, view_size, 1, AOI_WATCHER | AOI_MARHER)
    else
        self.space:insert(id, x, y, 0, 0, 1, AOI_MARHER)
    end
    self:update_aoi_event()
end

function AoiModel:update(id, x, y, view_size)
    self.space:update(id, x, y, view_size, view_size, 1)
    self:update_aoi_event()
end

function AoiModel:fire_event(id, eventid, fn)
    self.space:fire_event(id, eventid)
    self:update_aoi_event(fn)
end

function AoiModel:erase(id)
    local res = self.space:erase(id)
    self:update_aoi_event()
    return res
end

function AoiModel:query(x, y, view_w, view_h)
    x         = mfloor(x)
    y         = mfloor(y)
    view_w    = 2 * mceil(view_w)
    view_h    = 2 * mceil(view_h)
    local out = {}
    self.space:query(x, y, view_w, view_h, out)
    return out
end

function AoiModel:update_aoi_event(fn)
    local count = self.space:update_event(self.event_cache)
    for i = 1, count, 3 do
        local watcher = self.event_cache[i]
        local marker  = self.event_cache[i + 1]
        local eventid = self.event_cache[i + 2]
        if eventid == EVENT_ENTER then
            self:enter_ev(watcher, marker)
        elseif eventid == EVENT_LEAVE then
            self:leave_ev(watcher, marker)
        else
            fn(watcher)
        end
    end
end

function AoiModel:enter_ev(watcher, marker)
    log_debug("[AoiModel][enter_ev] watcher:%s,marker:%s", watcher, marker)
end

function AoiModel:leave_ev(watcher, marker)
    log_debug("[AoiModel][leave_ev] watcher:%s,marker:%s", watcher, marker)
end

return AoiModel
