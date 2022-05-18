-- wheel_map.lua
local qhash_code = hive.hash_code

local WheelMap   = class()
local prop       = property(WheelMap)
prop:reader("host_maps", {})    -- 真实的map
prop:reader("wheel_cnt", 1)     -- 轮子数量（最小为1）
prop:reader("wheel_cur", 1)     -- 当前轮子号
prop:reader("count", 0)         -- 数量

function WheelMap:__init(wheel_cnt)
    self.wheel_cnt = wheel_cnt or 1
    for n = 1, self.wheel_cnt do
        self.host_maps[n] = {}
    end
end

-- 设置指定key的值
function WheelMap:set(key, value)
    local wheel_no = qhash_code(key, self.wheel_cnt)
    local host_map = self.host_maps[wheel_no]
    if not host_map[key] and value then
        self.count = self.count + 1
    elseif host_map[key] and not value then
        self.count = self.count - 1
    end
    host_map[key] = value
end

-- 获取指定key的值
function WheelMap:get(key)
    if not key then
        return nil
    end
    local wheel_no = qhash_code(key, self.wheel_cnt)
    local host_map = self.host_maps[wheel_no]
    return host_map[key]
end

-- 正常遍历
function WheelMap:iterator()
    local key       = nil
    local host_maps = self.host_maps
    local wheel     = next(host_maps)
    local host_map  = host_maps[wheel]
    local function iter()
        :: label_continue ::
        key = next(host_map, key)
        if key then
            return key, host_map[key]
        end
        wheel = next(host_maps, wheel)
        if wheel then
            host_map = host_maps[wheel]
            goto label_continue
        end
    end
    return iter
end

-- 带轮遍历
function WheelMap:wheel_iterator()
    local key       = nil
    local wheel_cur = self.wheel_cur
    local host_map  = self.host_maps[wheel_cur]
    self.wheel_cur  = (wheel_cur < self.wheel_cnt) and wheel_cur + 1 or 1
    local function iter()
        key = next(host_map, key)
        if key then
            return key, host_map[key]
        end
    end
    return iter
end

-- export
return WheelMap
