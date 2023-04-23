local sformat      = string.format
local CheckValid = {
	funcs = {},
	multi_table = {},
	multi_check_func = {},
	multi_table_name = {}
}

CheckValid.__index      = CheckValid

function CheckValid:set_check_func(table_name, keys, check_func)
	self.funcs[table_name] = { keys = keys, func = check_func }
end

function CheckValid:set_multi_table_check(table_name_list, func)
	for _, v in ipairs(table_name_list) do
		self.multi_table_name[v.name] = v.fields
	end

	self.multi_check_func = func
end

function CheckValid:check_by_multi_table()
	local ok, err_str = self.multi_check_func(self.multi_table)
	if not ok then
		return false, err_str
	end

	return true
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
			if self.multi_table_name[table_name] then
				if not self.multi_table[table_name] then
					self.multi_table[table_name] = {}
				end
				local data = {}
				for _, field in ipairs(self.multi_table_name[table_name]) do
					data[field] = v[field]
				end
				table.insert(self.multi_table[table_name], data)
			end

			for index, key_list in ipairs(keys) do
				if #key_list == 0 then
					goto continue
				end

				local data = primary_record
				if not data[index] then
					data[index] = {}
				end
				data = data[index]

				for _, key in ipairs(key_list) do
					if not v[key] then
						return false, sformat("key not exists, key : %s", key)
					end

					if not data[v[key]] then
						data[v[key]] = {}
					else
						local err_str = sformat("repeated record")
						for i, _key in ipairs(key_list) do
							err_str = sformat("%s, %s : %s", err_str, _key, v[_key])
						end
						return false, err_str
					end

					data = data[v[key]]
				end

				::continue::
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