local sformat      = string.format
local CheckValid = {
    funcs = {}
}

CheckValid.__index      = CheckValid

function CheckValid:set_check_func(table_name, keys, check_func)
	self.funcs[table_name] = { keys = keys, func = check_func }
end

function CheckValid:get_check_func(table_name)
    return self.funcs[table_name]
end

function CheckValid:check(table_name, records)
	if not self.funcs[table_name] then
		return true
	end

	local keys = self.funcs[table_name].keys
	if keys and #keys > 0 then
		local primary_record = {}
		for _, v in ipairs(records) do
			local data = primary_record
			local has_data = false
			local values = {}
			for _, key in ipairs(keys) do
				if not v[key] then
					return false, sformat("key not exists, key : %s", key)
				end

				if not data[v[key]] then
					data[v[key]] = {}
					has_data = false
				else
					has_data = true
				end

				data = data[v[key]]
				table.insert(values, v[key])
			end

			if has_data then
				local err_str = sformat("repeated record")
				for i, v in ipairs(keys) do
					err_str = sformat("%s, %s : %s", err_str, v, values[i])
				end
				return false, err_str
			end
		end
	end

	if self.funcs[table_name].func then
		return self.funcs[table_name].func(records)
	end

	return true
end
hive.check_valid = CheckValid

return CheckValid