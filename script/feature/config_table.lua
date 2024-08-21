--cfg_table.lua
local next             = next
local pairs            = pairs
local ipairs           = ipairs
local sformat          = string.format
local tconcat          = table.concat
local tinsert          = table.insert
local tunpack          = table.unpack
local tointeger        = math.tointeger
local tonumber         = tonumber
local tsort            = table.sort
local log_err          = logger.err
local log_info         = logger.info
local trandom_array    = table_ext.random_array
local import_file_time = hive.import_file_time

local TABLE_MAX_INDEX  = 4

local ConfigTable      = class()
local prop             = property(ConfigTable)
prop:reader("name", nil)
prop:reader("rows", {})
prop:reader("indexs", nil)
prop:reader("count", 0)
prop:accessor("version", 0)
prop:reader("load_time", 0)
prop:reader("groups", {})
prop:reader("group_keys", {})

-- 初始化一个配置表，indexs最多支持三个
function ConfigTable:__init()
end

function ConfigTable:set_records(file_name)
    local records = import(file_name)
    if records == nil then
        log_err("[ConfigTable][set_records] config is not exist:{}", file_name)
        return
    end
    if type(records) ~= "table" then
        log_err("[ConfigTable][set_records] config is not correct:{}", file_name)
        return
    end
    self.rows = {}
    self:check_index(records)
    for _, row in pairs(records) do
        self:upsert(row)
    end
    self.load_time = import_file_time(file_name)
    --重构组索引
    for key_name, _ in pairs(self.group_keys) do
        self:init_group(key_name)
    end
end

function ConfigTable:name_to_filename(name)
    return sformat("%s_cfg.lua", name)
end

function ConfigTable:setup(name, ...)
    local file_name = self:name_to_filename(name)
    if self.load_time > 0 and import_file_time(file_name) == self.load_time then
        return false
    end
    if self.load_time > 0 then
        log_info("[ConfigTable][setup] reload config {}", file_name)
    end
    if self:setup_nil(name, ...) then
        self:set_records(file_name)
    end
    return true
end

function ConfigTable:setup_nil(name, ...)
    local size = select("#", ...)
    if size > 0 and size < TABLE_MAX_INDEX then
        self.name   = name
        self.indexs = { ... }
        return true
    else
        log_err("[ConfigTable][__init] keys len illegal. name={}, size={}", name, size)
    end
    return false
end

--生成index
function ConfigTable:build_index(...)
    local n = select("#", ...)
    if n == 1 then
        return ...
    end
    if n > 0 then
        return tconcat({ ... }, "@@")
    end
end

function ConfigTable:check_index(records)
    local tmp_indexs = {}
    for _, v in pairs(records) do
        local row_indexs = {}
        for _, index in ipairs(self.indexs) do
            row_indexs[#row_indexs + 1] = v[index]
        end
        local row_index = self:build_index(tunpack(row_indexs))
        if not row_index then
            log_err("[ConfigTable][check_index] row_index is nil:{}", self.name)
            return false
        end
        if not tmp_indexs[row_index] then
            tmp_indexs[row_index] = true
        else
            log_err("[ConfigTable][check_index] {} row_index is not unique row:{}", self.name, v)
            return false
        end
    end
    return true
end

-- 更新一行配置表
function ConfigTable:upsert(row)
    if not self.indexs then
        return
    end
    local row_indexs = {}
    for _, index in ipairs(self.indexs) do
        row_indexs[#row_indexs + 1] = row[index]
    end
    if #row_indexs ~= #self.indexs then
        log_err("[ConfigTable][upsert] row data index lost. row={}, indexs={}", row, self.indexs)
        return
    end
    local row_index = self:build_index(tunpack(row_indexs))
    if row_index then
        if not self.rows[row_index] then
            self.count = self.count + 1
        end
        self.rows[row_index] = row
    end
end

-- 设置group组
function ConfigTable:init_group(key_name)
    local keys = self.group_keys[key_name]
    if not keys then
        return
    end
    self.groups[key_name] = {}
    local groups          = self.groups[key_name]
    for _, row in pairs(self.rows) do
        local group_keys = {}
        for _, index in ipairs(keys) do
            group_keys[#group_keys + 1] = row[index]
        end
        if #group_keys ~= #keys then
            log_err("[ConfigTable][upsert_group] row data index lost. row={}, group_keys={}", row, keys)
            return
        end
        local group_index = self:build_index(tunpack(group_keys))
        if group_index then
            local group = groups[group_index]
            if not group then
                groups[group_index] = { row }
            else
                tinsert(group, row)
            end
        end
    end
end

-- 获取一项，
-- ...必须与初始化index对应。
function ConfigTable:find_one(...)
    local row_index = self:build_index(...)
    if not row_index then
        log_err("[ConfigTable][find_one] table {} row index is nil.", self.name)
        return
    end
    local row = self.rows[row_index]
    if not row then
        log_err("[ConfigTable][find_one] table={} row data not found. index={},ref:{}", self.name, row_index, hive.where_call())
    end
    return row
end

-- 获取一项，
-- ...必须与初始化index对应。
function ConfigTable:try_find_one(...)
    local row_index = self:build_index(...)
    return self.rows[row_index]
end

-- 获取一项的指定key值，
-- ...必须与初始化index对应。
function ConfigTable:find_value(key, ...)
    local row = self:find_one(...)
    if row then
        return row[key]
    end
end

-- 获取一项的指定key值，
-- ...必须与初始化index对应。
function ConfigTable:find_number(key, ...)
    local row = self:find_one(...)
    if row then
        return tonumber(row[key])
    end
end

-- 获取一项的指定key值，
-- ...必须与初始化index对应。
function ConfigTable:find_integer(key, ...)
    local row = self:find_one(...)
    if row then
        return tointeger(row[key])
    end
end

--构建分组索引
function ConfigTable:create_group_index(key_name, ...)
    local size = select("#", ...)
    if size > 0 and size < TABLE_MAX_INDEX then
        self.group_keys[key_name] = { ... }
        self:init_group(key_name)
        return true
    else
        log_err("[ConfigTable][create_group_index] keys len illegal. group_index={}", { ... })
    end
    return false
end

--查询分组数据
function ConfigTable:find_group(key_name, ...)
    local group_index = self:build_index(...)
    if not group_index then
        log_err("[ConfigTable][find_group] table {} row group_index is nil.[{}]", self.name, { ... })
        return
    end
    local groups = self.groups[key_name]
    if not groups then
        log_err("[ConfigTable][find_group] the group key is not init:{}", key_name)
        return
    end
    local group = groups[group_index]
    if not group then
        log_info("[ConfigTable][find_group] table={} row group not found. index={}", self.name, group_index)
    end
    return group
end

-- 获取所有项，参数{field1=val1,field2=val2,field3=val3}，与初始化index无关
function ConfigTable:select(query, single)
    local rows = {}
    for _, row in pairs(self.rows) do
        for field, value in pairs(query or {}) do
            if row[field] ~= value then
                goto continue
            end
        end
        rows[#rows + 1] = row
        if single then
            return rows
        end
        :: continue ::
    end
    return rows
end

-- 获取随机一项，参数{field1=val1,field2=val2,field3=val3}，与初始化index无关
function ConfigTable:select_random(query, single)
    local rows = self:select(query, single)
    if #rows > 0 then
        return trandom_array(rows)
    end
    return nil
end

--迭代器
function ConfigTable:iterator()
    local index = nil
    local rows  = self.rows
    local function iter()
        index = next(rows, index)
        if index then
            return index, rows[index]
        end
    end
    return iter
end

-- 顺序迭代器
-- @param cmp 比较函数
function ConfigTable:siterator(cmp)
    local sort_keys = {}
    for _, v in pairs(self.rows) do
        sort_keys[#sort_keys + 1] = v
    end
    local sortfunc
    if cmp then
        sortfunc = function(a, b)
            return cmp(a, b)
        end
    else
        sortfunc = function(a, b)
            return a < b
        end
    end
    tsort(sort_keys, sortfunc)

    local index = nil
    local function iter()
        index = next(sort_keys, index)
        if index then
            return index, sort_keys[index]
        end
    end
    return iter
end

return ConfigTable
