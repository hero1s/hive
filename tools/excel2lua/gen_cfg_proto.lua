local sfind      = string.find
local ssub       = string.sub
local smatch     = string.gmatch

local input_path = "../../proto/activity_cfg.proto"

--移除首尾空格
local function trim(str)
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

local gen_cfg_proto = {}

local PhaseType     = {
    NONE    = 1,
    MESSAGE = 2,
    BRACKET = 3,
}

local proto_type    = {
    ["int"]    = "int32",
    ["float"]  = "float",
    ["byte"]   = "string",
    ["bool"]   = "bool",
    ["string"] = "string",
    ["text"]   = "string",
    ["date"]   = "int32",
}

function gen_cfg_proto:init()
    self.phase           = PhaseType.NONE
    self.message         = {}
    self.message_name    = nil

    self.excel_header    = {}
    self.activity_header = {}
end

function gen_cfg_proto:add_excel_header(title, value)
    for _, v in ipairs(self.excel_header) do
        if v.name == title then
            table.insert(v.field_list, value)
            return
        end
    end

    local header = { name = title, field_list = { value } }
    table.insert(self.excel_header, header)
end

function gen_cfg_proto:parse_type(field_type)
    if string.sub(field_type, 1, 5) == "array" then
        return "array"
    elseif string.sub(field_type, 1, 6) == "struct" then
        return "struct"
    else
        return field_type
    end
end

function gen_cfg_proto:need_gen(name)
    if #name <= 2 then
        return true
    end

    if ssub(name, #name - 1, #name) == "_0" then
        return false
    end

    return true
end

function gen_cfg_proto:parse_name(name, field_type)
    local new_name = name
    local pos      = sfind(new_name, "_0")
    if pos then
        new_name = ssub(new_name, 1, pos - 1)
    end

    if string.sub(field_type, 1, 5) == "array" then
        local new_pos = sfind(new_name, '%(')
        if not new_pos then
            if pos then
                return new_name
            else
                print("----------- name is error : ", name)
                return nil
            end
        end

        new_name = ssub(new_name, 1, new_pos - 1)
        if not new_name then
            print("----------- name is error : ", name)
        end
    elseif string.sub(field_type, 1, 6) == "struct" then
        local new_pos = sfind(new_name, '<')
        if not new_pos then
            if pos then
                return new_name
            else
                print("----------- name is error : ", name)
            end
        end

        new_name = ssub(new_name, 1, new_pos - 1)
        if not new_name then
            print("----------- name is error : ", name)
        end
    end

    return new_name
end

function gen_cfg_proto:process_excel_header(title, field_type, name)
    local pos = sfind(name, "_0", -1)
    if pos then
        name = ssub(name, 1, #name - 2)
    end

    local value = self:parse_excel_header(field_type, name)
    if not value then
        print("[gen_cfg_proto][process_excel_header] error, title : ", title, ", field_type : ", field_type, ", name : ", name)
        return false
    end

    self:add_excel_header(title, value)
    return true
end

function gen_cfg_proto:parse_excel_header(field_type, name)
    field_type = trim(field_type)
    name       = trim(name)
    if proto_type[field_type] then
        return { type = proto_type[field_type], plain = true, name = name }
    end

    if string.sub(field_type, 1, 5) == "array" then
        return self:parse_excel_array_header(field_type, name)
    elseif string.sub(field_type, 1, 6) == "struct" then
        return self:parse_excel_struct_header(field_type, name)
    else
        print("[parse_excel_header]type not exists, excel : ", field_type, name, #field_type)
        return nil
    end
end

function gen_cfg_proto:parse_excel_array_header(field_type, name)
    local head_bracket = sfind(field_type, '%(')
    if not head_bracket then
        print("[parse_excel_array_header]type field format error(array lack '('), field type : " .. field_type)
        return nil
    end

    local name_head_bracket = sfind(name, '%(')
    if not name_head_bracket then
        print("[parse_excel_array_header]name field format error(array lack ')'), name : " .. name)
        return nil
    end

    local value = self:parse_excel_header(string.sub(field_type, head_bracket + 1, #field_type - 1), string.sub(name, name_head_bracket + 1, #name - 1))
    if not value then
        print("[parse_excel_array_header]parse header failed, field_type : " .. field_type .. ", name : " .. name)
        return nil
    end

    return { type = "array", value = value, name = string.sub(name, 1, name_head_bracket - 1) }
end

function gen_cfg_proto:parse_excel_struct_header(field_type, name)
    local head_bracket = sfind(field_type, '<')
    if not head_bracket then
        print("[parse_excel_struct_header]struct field format error(lack '<'), field type : " .. field_type)
        return nil
    end

    local field_array = {}
    for field in string.gmatch(field_type, '[^,^<^>)]*', 1) do
        if field ~= '' then
            table.insert(field_array, field)
        end
    end

    if #field_array <= 1 then
        print("[parse_excel_struct_header]field_type error, name : ", name)
        return nil
    end

    local name_array = {}
    for word in string.gmatch(name, '[^,^>^<]*', 1) do
        if word ~= '' then
            table.insert(name_array, word)
        end
    end

    if #name_array ~= #field_array then
        print("[parse_excel_struct_header]name count not equal with field count, name : ", name)
        return nil
    end

    local value_array = {}
    for i = 2, #name_array do
        local value = self:parse_excel_header(field_array[i], name_array[i])
        if not value then
            print("[parse_excel_struct_header]parse header failed, name : ", name_array[i])
            return nil
        end
        table.insert(value_array, value)
    end

    return { type = "struct", value = value_array, name = name_array[1] }
end

function gen_cfg_proto:load_proto(file_path)
	os.execute("git checkout " .. file_path)
    local handle = io.open(file_path, 'r')
    if not handle then
        return true
    end

    local line = handle:read()
    while line do
        if not self:parse_line(line) then
            print("parse proto file failed, path : ", file_path)
            return false
        end
        line = handle:read()
    end

    return true
end

function gen_cfg_proto:parse_line(line)
    line = trim(line)
    if #line == 0 or ssub(line, 1, 2) == "//" or sfind(line, "syntax") then
        return true
    end

    if self.phase == PhaseType.NONE then
        if not sfind(line, "message") then
            return true
        end

        return self:parse_message(line)
    elseif self.phase == PhaseType.MESSAGE then
        return self:parse_left_bracket(line)
    elseif self.phase == PhaseType.BRACKET then
        return self:parse_field(line)
    end
end

function gen_cfg_proto:parse_message(line)
    local word_list = {}
    for word in string.gmatch(line, '[%a%d_]+', 1) do
        table.insert(word_list, word)
    end

    if #word_list < 2 then
        print("message line error : ", line)
        return false
    end

    self.message_name               = word_list[2]
    self.phase                      = PhaseType.MESSAGE
    self.message[self.message_name] = {
        _max_seq = 0
    }
    return true
end

function gen_cfg_proto:parse_left_bracket(line)
    if ssub(line, 1, 1) ~= '{' then
        print("lack left bracket, line : ", line)
        return false
    end

    self.phase = PhaseType.BRACKET
    return true
end

function gen_cfg_proto:parse_field(line)
    if ssub(line, 1, 1) == '}' then
        self.phase        = PhaseType.NONE
        self.message_name = nil
        self.message_max  = 0
        return true
    end

    local word_list = {}
    for word in string.gmatch(line, '[%a%d=_]+', 1) do
        table.insert(word_list, word)
    end

    local equal_pos = 0
    for index, word in ipairs(word_list) do
        if word == "=" then
            equal_pos = index
            break
        end
    end

    if equal_pos >= #word_list then
        print("field data error, line : ", line, equal_pos, #word_list)
        return false
    end

    local field_sequence = word_list[equal_pos + 1]
    local semicolon_pos  = sfind(word_list[equal_pos + 1], ";")
    if semicolon_pos then
        field_sequence = string.sub(field_sequence, 1, #field_sequence - 1)
    end

    if self.message[self.message_name]._max_seq < tonumber(field_sequence) then
        self.message[self.message_name]._max_seq = tonumber(field_sequence)
    end

    local type                                                = word_list[equal_pos - 2]
    self.message[self.message_name][word_list[equal_pos - 1]] = { seq = field_sequence, type = type, array = equal_pos > 3 }
    --print("--------------", self:serialize(word_list), field_sequence, type, equal_pos)
    return true
end

function gen_cfg_proto:format_struct(field)
    local struct_list = {}
    for _, v in ipairs(field.value) do
        if v.type == "array" then
            local value = v.value
            table.insert(struct_list, { option = v.type, name = v.name, type = value.name })
            self:format_array(value)
        elseif v.type == "struct" then
            local value = v.value
            table.insert(struct_list, { name = v.name, type = value.name })
            self:format_struct(value)
        else
            table.insert(struct_list, { name = v.name, type = v.type })
        end
    end

    table.insert(self.activity_header, { name = field.name, value = struct_list })
end

function gen_cfg_proto:format_array(field)
    if field.plain then
        return
    end

    if field.type == "array" then
        self:format_array(field.value)
    elseif field.type == "struct" then
        self:format_struct(field.value)
    end
end

function gen_cfg_proto:format_excel_header()
    for _, header in ipairs(self.excel_header) do
        local cfg_name = header.name .. "_cfg"
        local seq_list = {}
        for _, field in ipairs(header.field_list) do
            if field.plain then
                table.insert(seq_list, { type = field.type, name = field.name })
                goto continue
            end

            if field.type == "array" then
                local value = field.value
                if value.type == "struct" then
                    table.insert(seq_list, { option = field.type, name = field.name, type = value.name })
                    self:format_struct(value)
                elseif value.type == "array" then
                    table.insert(seq_list, { option = field.type, name = field.name, type = value.name })
                    self:format_array(value)
                else
                    table.insert(seq_list, { option = field.type, name = field.name, type = value.type })
                end
            else
                print("[format_excel_header]error type : ", field.type)
                return false
            end
            :: continue ::
        end

        table.insert(self.activity_header, { name = cfg_name, value = seq_list })
    end

    return true
end

function gen_cfg_proto:process_field_seq()
    for _, v in ipairs(self.activity_header) do
        local local_message = self.message[v.name]
        if not local_message then
            goto continue
        end

        local value = v.value
        for index, field in ipairs(value) do
            if local_message[field.name] then
                field.seq = local_message[field.name].seq
                if field.type ~= local_message[field.name].type then
                    print(string.format("------------------not allow change field type, new type : %s, old type : %s", field.type, local_message[field.name].type))
                    return false
                end
            else
                if index > local_message._max_seq then
                    field.seq = index
                else
                    field.seq              = local_message._max_seq + 1
                    local_message._max_seq = local_message._max_seq + 1
                end
            end
        end

        for i = 1, #value do
            for j = i + 1, #value do
                if tonumber(value[i].seq) > tonumber(value[j].seq) then
                    local tmp = value[i]
                    value[i]  = value[j]
                    value[j]  = tmp
                end
            end
        end

        :: continue ::
    end

    return true
end

function gen_cfg_proto:exec_gen()
    self:load_proto(input_path)
    self:format_excel_header()
    if not self:process_field_seq() then
        return false
    end
    local data = 'syntax = "proto3";\n\npackage ncmd_cs.lobby;\n'
	local processd_name_list = {}
    for _, v in ipairs(self.activity_header) do
		if processd_name_list[v.name] then
			goto continue
		end

		processd_name_list[v.name] = true
        data              = string.format("%s\nmessage %s\n{", data, v.name)
        local index       = 1
        local name_space  = 0
        local equal_space = 0
        for _, field in ipairs(v.value) do
            local cur_space = 0
            if field.option then
                cur_space = cur_space + math.ceil((#field.type + 10) / 4) * 4
                cur_space = cur_space + 4
            else
                cur_space = cur_space + math.ceil(#field.type / 4) * 4
                cur_space = cur_space + 4
            end

            if cur_space > name_space then
                name_space = cur_space
            end


            cur_space = math.ceil((#field.name) / 4) * 4
            if cur_space > equal_space then
                equal_space = cur_space
            end
        end

        for _, field in ipairs(v.value) do
            local str = ""
            if field.option then
                str = string.format("    repeated %s", field.type)
            else
                str = string.format("    %s", field.type)
            end

            for i = 1, name_space - #str do
                str = string.format("%s ", str)
            end

            str = string.format("%s%s", str, field.name)
            for i = 1, equal_space - #field.name do
                str = string.format("%s ", str)
            end

            data  = string.format("%s\n%s = %s;", data, str, field.seq or index)
            index = index + 1
        end

        data = string.format("%s\n}\n", data)
		::continue::
    end

    local file, err = io.open(input_path, 'w')
    if not file then
        print("open file failed, err : %s", err)
        return false
    end

    file:write(data)
    --print(data)

    return true
end

function gen_cfg_proto:serialize(obj)
    local lua = ""
    local t   = type(obj)
    if t == "number" then
        lua = lua .. obj
    elseif t == "boolean" then
        lua = lua .. tostring(obj)
    elseif t == "string" then
        lua = lua .. string.format("%q", obj)
    elseif t == "table" then
        lua            = lua .. "{"

        local need_del = false
        for k, v in pairs(obj) do
            lua      = lua .. "[" .. self:serialize(k) .. "]=" .. self:serialize(v) .. ","
            need_del = true
        end

        if need_del then
            lua = string.sub(lua, 1, #lua - 1)
        end

        local metatable = getmetatable(obj)
        if metatable ~= nil and type(metatable.__index) == "table" then
            for k, v in pairs(metatable.__index) do
                lua = lua .. "[" .. self:serialize(k) .. "]=" .. self:serialize(v) .. ","
            end

            lua = string.sub(lua, 1, #lua - 1)
        end
        lua = lua .. "}"
    elseif t == "nil" then
        return nil
    else
        error("can not serialize a " .. t .. " type.")
    end
    return lua
end

return gen_cfg_proto