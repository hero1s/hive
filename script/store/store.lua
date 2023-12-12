--store.lua
local bdate        = bson.date
local log_err      = logger.err
local log_debug    = logger.debug
local check_failed = hive.failed

local mongo_agent  = hive.get("mongo_agent")
local cache_agent  = hive.get("cache_agent")

local Store        = class()
local prop         = property(Store)
prop:reader("sheet", "")        -- sheet
prop:reader("primary_key", "")
prop:reader("primary_id", "")   -- primary_id
prop:reader("cache", true)      -- is cache
prop:reader("dirty", false)
prop:reader("loaded", false)
prop:accessor("data", nil)

function Store:__init(sheet, primary_key, primary_id, cache)
    self.sheet       = sheet
    self.primary_key = primary_key
    self.primary_id  = primary_id
    self.cache       = cache or true
end

function Store:on_prop_changed(key, value)
    if key == "data" then
        self.dirty = true
        log_debug("[Store][on_prop_changed] sheet:{},primary_id:{}", self.sheet, self.primary_id)
    end
end

function Store:save(flush)
    if not self.dirty then
        return true
    end
    self.dirty            = false
    self.data.update_time = bdate(hive.now)
    if self.cache then
        local ec = cache_agent:update(self.primary_id, self.data, self.sheet, flush)
        if check_failed(ec) then
            log_err("[Store][save] table={},primary_id={},ec={},data:{}", self.sheet, self.primary_id, ec, self.data)
            self.dirty = true
            return false
        end
    else
        local ok = mongo_agent:update_sheet(self.sheet, self.primary_id, self.primary_key, self.data)
        if not ok then
            log_err("[Store][save] table={},primary_id={},data:{}", self.sheet, self.primary_id, self.data)
            self.dirty = true
            return false
        end
    end
    return true
end

function Store:load()
    if self.cache then
        local code, data = cache_agent:load(self.primary_id, self.sheet)
        if check_failed(code) then
            log_err("[Store][load] table={},primary_id={},ec={},data:{}", self.sheet, self.primary_id, code, data)
            return false
        end
        self.data = data
    else
        local ok, data = mongo_agent:load_sheet(self.sheet, self.primary_id, self.primary_key, self.data)
        if not ok then
            log_err("[Store][load] table={},primary_id={},data:{}", self.sheet, self.primary_id, data)
            return false
        end
        self.data = data
    end
    self.loaded = true
    return true
end

return Store
