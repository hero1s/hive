--main_convertor.lua
local lcrypt = require('lcrypt')
local lstdfs = require('lstdfs')
local lexcel = require('luaxlsx')

require("check_valid")
local check_valid   = hive.check_valid

local type          = type
local pairs         = pairs
local tostring      = tostring
local iopen         = io.open
local hgetenv       = os.getenv
local otime         = os.time
local ldir          = lstdfs.dir
local lmkdir        = lstdfs.mkdir
local lappend       = lstdfs.append
local lconcat       = lstdfs.concat
local lfilename     = lstdfs.filename
local lcurdir       = lstdfs.current_path
local lmd5          = lcrypt.md5
local sfind         = string.find
local sgsub         = string.gsub
local sformat       = string.format
local smatch        = string.match
local tconcat       = table.concat
local tinsert       = table.insert
local tunpack       = table.unpack
local mtointeger    = math.tointeger
local slower        = string.lower

local version       = 10000

local file_names    = {}
--指定导出函数
local export_method = nil
--类型定义行，默认2
local type_line     = 2
--表头定义行,默认4
local head_line     = 4
--数据起始行,默认5
local start_line    = head_line + 1

--设置utf8
if hive.platform == "linux" then
    local locale = os.setlocale("C.UTF-8")
    if not locale then
        print("switch utf8 mode failed!")
    end
else
    local locale = os.setlocale(".UTF8")
    if not locale then
        print("switch utf8 mode failed!")
    end
end

local function conv_integer(v)
    return mtointeger(tonumber(v)) or 0
end

local function conv_number(v)
    return mtointeger(v) or tonumber(v) or 0
end

--28800 => 3600 * 8
--86400 => 3600 * 24
--25569 => 1970.1.1 0:0:0
--根据fmt_code和fmt_id解析自定义格式
local function cell_value_fmt_parse(cell)
    if cell.type == "date" then
        if cell.fmt_id == 14 then
            return 86400 * (cell.value - 25569) - 28800
        end
    elseif cell.type == "custom" then
        if sfind(cell.fmt_code, "yy") then
            return 86400 * (cell.value - 25569) - 28800
        end
        if sfind(cell.fmt_code, "mm:ss") then
            return 86400 * cell.value
        end
    end
end

local value_func = {
    ["int"]    = conv_number,
    ["float"]  = conv_number,
    ["byte"]   = conv_integer,
    ["bool"]   = function(value)
        return value == "1"
    end,
    ["string"] = function(value)
        return value
    end,
    ["text"]   = function(value)
        return value
    end,
    ["array"]  = function(value)
        value = slower(value)
        if sfind(value, '[(]') then
            -- 替换'('&')' 为 '{' & '}'
            return sgsub(value, '[(.*)]', function(s)
                return s == '(' and '{' or '}'
            end)
        else
            return '{' .. value .. '}'
        end
    end,
}

--转数值
local function convert_value(value, field_type)
    if field_type then
        local func = value_func[field_type]
        if func then
            return func(value)
        end
    end
    return value
end

--获取cell value
local function get_sheet_value(sheet, row, col, field_type, header)
    local cell = sheet.get_cell(row, col)
    if cell and cell.type ~= "blank" then
        local value                            = cell.value
        --------------------------------------兼容了文本格式的转换，后期可以去掉 modify toney 2021/7/15------------------
        local year, month, day, hour, min, sec = smatch(cell.value, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
        if year and month and day and hour and min and sec then
            return otime({ day = day, month = month, year = year, hour = hour, min = min, sec = sec })
        end
        --------------------------------------兼容了文本格式的转换，后期可以去掉-------------------
        local fvalue = cell_value_fmt_parse(cell)
        if fvalue then
            value = fvalue
        end
        return convert_value(value, field_type)
    end
end

--导出到lua
--使用configmgr结构
local function export_records_to_struct(output, title, records)
    local table_name  = sformat("%s_cfg", title)
    local filename    = lappend(output, lconcat(table_name, ".lua"))
    local export_file = iopen(filename, "w")
    if not export_file then
        print(sformat("open output file %s failed!", filename))
        return
    end
    local lines       = {}
    lines[#lines + 1] = sformat("--%s.lua", table_name)
    lines[#lines + 1] = "--luacheck: ignore 631\n"
    lines[#lines + 1] = '--获取配置表\nlocal config_mgr = hive.get("config_mgr")'
    lines[#lines + 1] = sformat('local %s = config_mgr:get_table("%s")\n', title, title)

    lines[#lines + 1] = "--导出配置内容"
    for _, record in pairs(records) do
        for index, info in ipairs(record) do
            local key, value, ftype = tunpack(info)
            if index == 1 then
                lines[#lines + 1] = sformat("%s:upsert({", title)
            end
            if type(value) == "string" and ftype ~= "array" then
                value = "'" .. value .. "'"
                value = sgsub(value, "\n", "\\n")
            end
            lines[#lines + 1] = sformat("    %s = %s,", key, tostring(value))
        end
        lines[#lines + 1] = "})\n"
    end

    local output_data = tconcat(lines, "\n")
    export_file:write(output_data)
    export_file:write(sformat("\n%s:set_version('%s')", title, lmd5(output_data, 1)))
    export_file:close()
    print(sformat("export %s success!", filename))
end

--导出到lua
--使用luatable
local function export_records_to_table(output, title, records)
    local table_name  = sformat("%s_cfg", title)
    local filename    = lappend(output, lconcat(table_name, ".lua"))
    local export_file = iopen(filename, "w")
    if not export_file then
        print(sformat("open output file %s failed!", filename))
        return
    end
    local lines = {}
    tinsert(lines, sformat("--%s.lua", table_name))
    tinsert(lines, "--luacheck: ignore 631\n")
    tinsert(lines, "--导出配置内容")
    tinsert(lines, "return {")

    for _, record in pairs(records) do
        for index, info in ipairs(record) do
            local key, value, ftype, fdesc = tunpack(info)
            if index == 1 then
                tinsert(lines, "    {")
            end
            if type(value) == "string" and ftype ~= "array" then
                value = "'" .. value .. "'"
                value = sgsub(value, "\n", "\\n")
            end
            tinsert(lines, sformat("        %s = %s, --[[ %s ]]", key, tostring(value), fdesc))
        end
        tinsert(lines, "    },")
    end

    tinsert(lines, "}\n")

    local output_data = tconcat(lines, "\n")
    export_file:write(output_data)
    export_file:close()
    --检测表格合法性
    local data, err = loadfile(filename)
    if err then
        error(sformat([[
========================================================================
export %s error:%s!
========================================================================]], table_name, err))
    else
        local check_func = check_valid:get_check_func(table_name)
        if check_func then
            local records  = dofile(filename)
            local ret, err = check_func(records)
            if not ret then
                error(sformat([[
========================================================================
export %s error:%s!
========================================================================]], table_name, err))
            else
                print(sformat("export %s success and ----------->> check valid success!", table_name))
            end
            return
        end
        print(sformat("export %s success!", table_name))
    end
end

--导出到lua table
local function export_sheet_to_table(sheet, output, title)
    local header     = {}
    local field_type = {}
    local field_desc = {}
    for col = sheet.first_col, sheet.last_col do
        -- 读取第一行作为字段描述
        field_desc[col] = get_sheet_value(sheet, 1, col)
        -- 读取第二行服务器类型列，作为服务器筛选条件
        field_type[col] = get_sheet_value(sheet, type_line, col)
        -- 读取第四行作为表头
        header[col]     = get_sheet_value(sheet, head_line, col)
    end

    -- 如果此表不是服务器需要的,则不导出
    local svr_cols = 0
    for _, v in pairs(field_type) do
        if v then
            svr_cols = svr_cols + 1
        end
    end
    if svr_cols <= 1 then
        return false
    end

    local records    = {}
    local search_tag = true
    -- 从第五行开始处理
    for row = start_line, sheet.last_row do
        -- 搜索开始标记
        if search_tag then
            local start_tag = get_sheet_value(sheet, row, 1)
            if not start_tag or start_tag ~= "Start" then
                goto continue
            end
            search_tag = false
        end
        -- 遍历每一列
        local record, record_flag = {}, {}
        local pos                 = 0
        for col = 2, sheet.last_col do
            -- 过滤掉没有配置的行
            local ftype = field_type[col]
            if ftype then
                local key   = header[col]
                local value = get_sheet_value(sheet, row, col, ftype, key)
                if value ~= nil then
                    tinsert(record, { key, value, ftype, field_desc[col] })
                    pos              = pos + 1
                    record_flag[key] = 1
                elseif record_flag[key] == nil then
                    pos              = pos + 1
                    record_flag[key] = { pos, { key, value, ftype, field_desc[col] } }
                else
                    --多选一的列并且都没配

                end
            end
        end
        if #record > 0 then
            --填充缺失字段
            if next(record_flag) then
                local tmp = {}
                for _, v in pairs(record_flag) do
                    if type(v) == "table" then
                        tinsert(tmp, v)
                    end
                end
                --保持表格顺序一致
                table.sort(tmp, function(a, b)
                    return a[1] < b[1]
                end)
                for i, v in ipairs(tmp) do
                    local pos, value = tunpack(v)
                    --转换默认值 toney
                    value[2]         = convert_value("", value[3])
                    tinsert(record, pos, value)
                end
            end
            tinsert(records, record)
        end
        local end_tag = get_sheet_value(sheet, row, 1)
        if end_tag and end_tag == "End" then
            break
        end
        :: continue ::
    end
    export_method(output, title, records)

    return true
end

local function is_excel_file(file)
    if sfind(file, "~") then
        return false
    end
    local pos = sfind(file, "%.xlsm")
    if pos then
        return true
    end
    pos = sfind(file, "%.xlsx")
    if pos then
        return true
    end
    return false
end

--导出lua文件名
local function get_export_file_name(fname)
    local _, idx = fname:find(".*_")
    if idx then
        return slower(fname:sub(1, idx - 1))
    else
        idx = fname:match(".+()%.%w+$")
        if idx then
            return slower(fname:sub(1, idx - 1))
        end
        return slower(fname)
    end
end

--入口函数
local function export_excel(input, output, recursion)
    local files = ldir(input)
    for _, file in pairs(files) do
        local fullname = file.name
        if file.type == "directory" then
            if recursion then
                local fname   = lfilename(fullname)
                local soutput = lappend(output, fname)
                lmkdir(soutput)
                export_excel(fullname, soutput, recursion)
            end
            goto continue
        end
        if is_excel_file(fullname) then
            local workbook = lexcel.open(fullname)
            if not workbook then
                print(sformat("open excel %s failed!", fullname))
                goto continue
            end
            --只导出sheet1
            local sheets = workbook.sheets()
            local sheet  = sheets and sheets[1]
            if not sheet then
                print(sformat("export excel %s open sheet %d failed!", file, 0))
                break
            end
            local sheet_name = sheet.name
            if sheet.last_row < 4 or sheet.last_col <= 0 then
                print(sformat("export excel %s sheet %s empty!", file, sheet_name))
                break
            end

            local fname  = lfilename(fullname)
            local title  = get_export_file_name(fname)
            local ret    = export_sheet_to_table(sheet, output, title)
            if ret then
                if file_names[title] then
                    print(sformat("repeated sheet_name:%s old_name:%s file_name:%s", sheet_name, file_names[sheet_name], fullname))
                    goto continue
                end
                file_names[title] = fullname
            end
        end
        :: continue ::
    end
end

--检查配置
local function export_config()
    local input     = lcurdir()
    local output    = lcurdir()
    local env_input = hgetenv("HIVE_INPUT")
    if not env_input or #env_input == 0 then
        print("input dir not config!")
        input = input
    else
        input = lappend(input, env_input)
    end
    local env_output = hgetenv("HIVE_OUTPUT")
    if not env_output or #env_output == 0 then
        print("output dir not config!")
        output = output
    else
        output = lappend(output, env_output)
        lmkdir(output)
    end
    local env_version = hgetenv("HIVE_VERSION")
    if env_version then
        version = conv_integer(env_version)
    end
    local env_typline = hgetenv("HIVE_TYPLINE")
    if env_typline then
        type_line = mtointeger(env_typline)
    end
    local recursion = hgetenv("HIVE_RECURSION")
    if not recursion or math.tointeger(recursion) ~= 1 then
        recursion = false
    end
    local env_format = hgetenv("HIVE_FORMAT")
    export_method    = export_records_to_table
    if env_format and env_format == "struct" then
        export_method = export_records_to_struct
    end
    return input, output, recursion
end

--挂载表格校验逻辑
local function attach_check_valid()
    local valid_file = hgetenv("HIVE_VALID_FILE")
    if valid_file then
        require(valid_file)
    end
end
attach_check_valid()
print("useage: hive.exe [--input=xxx] [--output=xxx]")
print("begin export excels to lua!")

local input, output, recursion = export_config()
local ok, err                  = pcall(export_excel, input, output, recursion)
if not ok then
    print("export excel to lua failed:", err)
else
    print("success export excels to lua!")
end

os.exit()