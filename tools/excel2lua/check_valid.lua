local CheckValid = { funcs = {} }

function CheckValid.set_check_func(table_name, check_func)
    CheckValid.funcs[table_name] = check_func
end

function CheckValid.get_check_func(table_name)
    return CheckValid.funcs[table_name]
end

hive.check_valid = CheckValid

return CheckValid