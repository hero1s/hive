local sformat      = string.format
local CheckValid   = {
    funcs            = {}, --单表检测
    multi_table      = {}, --全表数据
    multi_check_func = {}, --全部检测函数
    foreign_keys     = {}, --外键检测
}

CheckValid.__index = CheckValid

function CheckValid:set_check_func(table_name, keys, check_func)
    self.funcs[table_name] = { keys = keys, func = check_func }
end

function CheckValid:set_foreign_keys(table_name, keys)
    self.foreign_keys[table_name] = keys
end

function CheckValid:add_multi_table_check(func)
    table.insert(self.multi_check_func, func)
end

function CheckValid:check_by_multi_table()
    print("begin check by multi table")
    for _, func in pairs(self.multi_check_func) do
        local ok, err_str = func(self.multi_table)
        if not ok then
            return false, err_str
        end
    end
    print("end check by multi table")
    return true
end

function CheckValid:check(table_name, records)
    self.multi_table[table_name] = records
    if not self.funcs[table_name] then
        return true
    end
    local keys        = self.funcs[table_name].keys
    local ok, err_str = self:check_keys(records, keys)
    if not ok then
        return ok, err_str
    end
    if self.funcs[table_name].func then
        return self.funcs[table_name].func(records)
    end
    return true
end

function CheckValid:check_keys(records, keys)
    if keys and #keys > 0 then
        local primary_record = {}
        for _, v in ipairs(records) do
            for index, key in ipairs(keys) do
                if not primary_record[index] then
                    primary_record[index] = {}
                end
                local data  = primary_record[index]
                local value = v[key]
                if not value then
                    return false, sformat("key not exists, key : %s", key)
                end
                if not data[value] then
                    data[value] = true
                else
                    return false, sformat("repeated record:%s,%s", key, value)
                end
            end
        end
    end
    return true
end

function CheckValid:check_foreign_keys()
    for table_name, keys in pairs(self.foreign_keys) do
        local datas = self.multi_table[table_name]
        if not datas then
            print(sformat("the foreign keys cfg is error:%s", table_name))
            goto continue
        end
        for _, v in pairs(keys) do
            local key, from_table, from_key = v.key, v.from_table, v.from_key
            local check_values              = {}
            for _, data in pairs(datas) do
                local value = data[key]
                if not check_values[value] and not self:is_exist_data(from_table, from_key, value) then
                    print(sformat("cfg error:the [%s] table:[%s][%s] is not exist:[%s][%s]!!!", table_name, key, value, from_table, from_key))
                end
                check_values[value] = true
            end
        end
        :: continue ::
    end
end

function CheckValid:is_exist_data(table_name, key, value)
    local records = self.multi_table[table_name]
    if not records then
        print(sformat("the foreign keys from table is nil:%s", table_name))
        return false
    end
    for _, v in pairs(records) do
        if v[key] == value then
            return true
        end
    end
    return false
end

hive.check_valid = CheckValid

return CheckValid