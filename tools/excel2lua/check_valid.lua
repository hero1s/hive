local CheckValid = {
    funcs = {}
}

CheckValid.__index      = CheckValid

function CheckValid:set_check_func(table_name, check_func)
    self.funcs[table_name] = check_func
end

function CheckValid:get_check_func(table_name)
    return self.funcs[table_name]
end

hive.check_valid = CheckValid

return CheckValid