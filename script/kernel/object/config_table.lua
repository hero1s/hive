--cfg_table.lua
local next            = next
local pairs           = pairs
local ipairs          = ipairs
local sformat         = string.format
local tconcat         = table.concat
local log_err         = logger.err

local TABLE_MAX_INDEX = 4

local ConfigTable     = class()
local prop            = property(ConfigTable)
prop:reader("name", nil)
prop:reader("rows", {})
prop:reader("indexs", {})
prop:reader("count", 0)
prop:accessor("version", 0)

-- 初始化一个配置表，indexs最多支持三个
function ConfigTable:__init()
end

function ConfigTable:setup(name, ...)
    if self:setup_nil(name, ...) then
        local file_name = sformat("%s_cfg", name)
        package.loaded[file_name] = nil
        local records = require(file_name)
        if records == nil then
            log_err("[ConfigTable][setup] config is not exist:%s", file_name)
            return
        end
        if type(records) ~= "table" then
            log_err("[ConfigTable][setup] config is not correct:%s", file_name)
            return
        end
        if not self:check_index(records) then
            log_err("[ConfigTable][setup] check_index error")
            --return
        end
        for _, row in pairs(records) do
            --log_debug("[ConfigTable][setup] set table %s cfg:%s", file_name, row)
            self:upsert(row)
        end
    end
end

function ConfigTable:setup_nil(name, ...)
    local size = select("#", ...)
    if size > 0 and size < TABLE_MAX_INDEX then
        self.name   = name
        self.indexs = { ... }
        return true
    else
        log_err("[ConfigTable][__init] keys len illegal. name=%s, size=%s", name, size)
    end
    return false
end

function ConfigTable:check_index(records)
    local tmp_indexs = {}
    for _, v in pairs(records) do
        local deploy = v.hive_deploy
        if deploy and deploy ~= hive.deploy then
            --部署环境不一样，不加载配置
            return
        end

        local row_indexs = {}
        for _, index in ipairs(self.indexs) do
            row_indexs[#row_indexs + 1] = v[index]
        end

        local row_index = tconcat(row_indexs, "@@")

        if not tmp_indexs[row_index] then
            tmp_indexs[row_index] = true
        else
            log_err("[ConfigTable][check_index] %s row_index is not unique row:%s", self.name, v)
            return false
        end
    end

    return true
end

-- 更新一行配置表
function ConfigTable:upsert(row)
    if not self.name then
        return
    end
    local deploy = row.hive_deploy
    if deploy and deploy ~= hive.deploy then
        --部署环境不一样，不加载配置
        return
    end
    local row_indexs = {}
    for _, index in ipairs(self.indexs) do
        row_indexs[#row_indexs + 1] = row[index]
    end
    if #row_indexs ~= #self.indexs then
        log_err("[ConfigTable][upsert] row data index lost. row=%s, indexs=%s", row, self.indexs)
        return
    end
    local row_index = tconcat(row_indexs, "@@")
    if row_index then
        if not self.rows[row_index] then
            self.count = self.count + 1
        end
        self.rows[row_index] = row
    end
end

-- 获取一项，
-- ...必须与初始化index对应。
function ConfigTable:find_one(...)
    local row_index = tconcat({ ... }, "@@")
    local row       = self.rows[row_index]
    if not row then
        log_err("[ConfigTable][find_one] table=%s row data not found. index=%s", self.name, row_index)
    end
    return row
end

-- 获取一项的指定key值，
-- ...必须与初始化index对应。
function ConfigTable:find_value(key, ...)
    local row = self:find_one(...)
    if row then
        return row[key]
    end
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

return ConfigTable
