--cmdline.lua
local load          = load
local ipairs        = ipairs
local log_err       = logger.err
local log_info      = logger.info
local log_warn      = logger.warn
local tpack         = table.pack
local smatch        = string.match
local sgmatch       = string.gmatch
local sformat       = string.format
local conv_number   = math_ext.conv_number
local conv_integer  = math_ext.conv_integer

--空白模式定义
local blank = "[%s]+"
--参数类型模式定义
--参数支持类型：table/float/integer/string
local patterns = {
    table = "({.*})",
    integer = "([%-]?%d+)",
    float = "([%-]?%d+[%.]?%d+)",
    string = "[\"\']?([^%s]-)[\"\']?",
}

local function conv_table(v)
    local code_func = load("return " .. v)
    if code_func then
        local t = code_func()
        if type(t) == "table" then
            return t
        end
    end
end

--转换参数
local function convert_arg(t, v)
    if type(v) == t then
        return v
    end
    if t == "integer" then
        return conv_integer(v)
    elseif t == "float" then
        return conv_number(v)
    elseif t == "table" then
        return conv_table(v)
    end
    return tostring(v)
end

--转换参数
local function convert_args(args, cmd_define)
    local define_args = cmd_define.args
    local fmtargs, fmtinfos = { args[1] }, { "cmd" }
    for i = 2, #args do
        local def_arg = define_args[i - 1]
        fmtinfos[#fmtinfos + 1] = def_arg.name
        fmtargs[#fmtargs + 1] = convert_arg(def_arg.type, args[i])
    end
    return {
        args = fmtargs,
        info = fmtinfos,
        name = args[1],
        type = cmd_define.type,
        service = cmd_define.service
    }
end

local Cmdline = singleton()
local prop = property(Cmdline)
prop:reader("command_defines", {})

function Cmdline:__init()
end

--选项解析器
--name: command name
--command : command command定义
--command 示例
--command = "player_id|integer aa|table bb|string dd|number"
function Cmdline:register_command(name, command, desc, comment, cmd_type, service)
    if self.command_defines[name] then
        log_warn("[Cmdline][register_command] command (%s) repeat registered!", name)
        return false
    end
    local def_args = {}
    local cmd_define = {type = cmd_type, desc = desc, comment = comment, command = command, service = service }
    for arg_name, arg_type in sgmatch(command, "([%a%d%_]+)|([%a%d%_]+)") do
        def_args[#def_args + 1] = {name = arg_name, type = arg_type}
    end
    cmd_define.args = def_args
    self.command_defines[name] = cmd_define
    log_info("[Cmdline][register_command] command (%s) registered!", name)
    return true
end


--参数解析
--cmd_data : table参数
function Cmdline:parser_data(cmd_data)
    local cmd_name = cmd_data.name
    local cmd_define = self.command_defines[cmd_name]
    if not cmd_define then
        log_err("[Cmdline][parser_data] invalid command (%s): isn't registered!", cmd_name)
        return nil, "invalid command: isn't registered"
    end
    local define_args = cmd_define.args
    local fmtargs, fmtinfos = { cmd_name }, { "cmd" }
    for i, def_arg in ipairs(define_args) do
        local arg = cmd_data[def_arg.name]
        if not arg then
            local err = sformat("invalid command: argument %s is not exist", def_arg.name)
            log_err("[Cmdline][parser_data] (%s) %s!", cmd_name, err)
            return nil, err
        end
        fmtinfos[#fmtinfos + 1] = def_arg.name
        fmtargs[#fmtargs + 1] = convert_arg(def_arg.type, arg)
    end
    return {
        args = fmtargs,
        info = fmtinfos,
        name = cmd_name,
        type = cmd_define.type,
        service = cmd_define.service
    }
end

--参数解析
--argument : 字符串参数
--argument = "push 123456 {dasd} dsadsad -12.36"
function Cmdline:parser_command(argument)
    local pattern = "([%a%d%_]+)"
    local cmd_name = smatch(argument, pattern)
    if not cmd_name then
        log_err("[Cmdline][parser_command] invalid command (%s): name parse error!", argument)
        return nil, "invalid command: name parse error"
    end
    local cmd_define = self.command_defines[cmd_name]
    if not cmd_define then
        log_err("[Cmdline][parser_command] invalid command (%s): isn't registered!", argument)
        return nil, "invalid command: isn't registered"
    end
    local define_args = cmd_define.args
    for _, def_arg in ipairs(define_args) do
        pattern = pattern .. blank .. patterns[def_arg.type]
    end
    local argsfunc = sgmatch(argument .. " ", pattern .. blank)
    if not argsfunc then
        log_err("[Cmdline][parser_command] invalid command (%s): format error!", argument)
        return nil, "invalid command: format error"
    end
    local args = tpack(argsfunc())
    if #args ~= (#define_args + 1) then
        local err = sformat("invalid command: argument need %d but get %d", #define_args, #args)
        log_err("[Cmdline][parser_command] (%s): %s!", argument, err)
        return nil, err
    end
    return convert_args(args, cmd_define)
end

hive.cmdline = Cmdline()

return Cmdline
