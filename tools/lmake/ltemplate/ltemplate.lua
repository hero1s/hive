--ltemplate.lua
local ipairs        = ipairs
local iopen         = io.open
local tconcat       = table.concat
local ssub          = string.sub
local sfind         = string.find
local sgsub         = string.gsub
local sformat       = string.format
local sgmatch       = string.gmatch

local open_tag = "{{%"
local close_tag = "%}}"
local equal_tag = "="

local function get_line(content, line_num)
    for line in sgmatch(content, "([^\n]*)\n?") do
    if line_num == 1 then
        return line
    end
    line_num = line_num - 1
    end
end

local function pos_to_line(content, pos)
    local line = 1
    local scontent = ssub(content, 1, pos)
    for _ in sgmatch(scontent, "\n") do
        line = line + 1
    end
    return line
end

local function error_for_line(code, source_line_no, err_msg)
    local source_line = get_line(code, source_line_no)
    return sformat("%s <[%s]: %s>", err_msg, source_line_no, source_line)
end

local function error_for_pos(code, source_pos, err_msg)
    local source_line_no = pos_to_line(code, source_pos)
    return error_for_line(code, source_line_no, err_msg)
end

local function parse_error(code, err)
    local line_no, err_msg = err:match("%[.-%]:(%d+): (.*)$")
    if not line_no then
        line_no, err_msg = err:match(".:(%d+): (.*)$")
    end
    if line_no then
        local err_res
        local line = get_line(code, tonumber(line_no))
        local source_line_no = tonumber(err:match("line (%d+)"))
        if source_line_no then
            err_res = error_for_line(code, tonumber(source_line_no), err_msg)
        end
        return sformat("%s <[%s]: %s>", err_res or err_msg, line_no, line)
    end
end

local function push_token(buffers, ...)
    for _, str in ipairs({...}) do
        buffers[#buffers + 1] = str
    end
end

local function compile_chunks(chunks)
    local buffers = {}
    push_token(buffers, "local _b, _b_i = {}, 0 \n")
    for _, chunk in ipairs(chunks) do
        local tpe = chunk[1]
        if "string" == tpe then
            push_token(buffers, "_b_i = _b_i + 1\n", "_b[_b_i] = ", sformat("%q", chunk[2]), "\n")
        elseif "code" == tpe then
            push_token(buffers, chunk[2], "\n")
        elseif "equal" == tpe then
            push_token(buffers, "_b_i = _b_i + 1\n", "_b[_b_i] = ",  chunk[2], "\n")
        end
    end
    push_token(buffers, "return _b")
    return tconcat(buffers)
end

local function push_chunk(chunks, kind, value)
    local chunk = chunks[#chunks]
    if chunk then
        if kind == "code" then
            chunk[2] = sgsub(chunk[2], "[ \t]+$", "")
            chunks[#chunks] = chunk
        end
        if chunk[1] == "code" and ssub(value, 1, 1) == "\n" then
            value = ssub(value, 2, #value)
        end
    end
    chunks[#chunks + 1] = { kind, value }
end

local function next_tag(chunks, content, ppos)
    local start, stop = sfind(content, open_tag, ppos, true)
    if not start then
        push_chunk(chunks, "string", ssub(content, ppos, #content))
        return false
    end
    if start ~= ppos then
        push_chunk(chunks, "string", ssub(content, ppos, start - 1))
    end
    ppos = stop + 1
    local equal
    if ssub(content, ppos, ppos) == equal_tag then
        equal = true
        ppos = ppos + 1
    end
    local close_start, close_stop = sfind(content, close_tag, ppos, true)
    if not close_start then
        return nil, error_for_pos(content, start, "failed to find closing tag")
    end
    push_chunk(chunks, equal and "equal" or "code", ssub(content, ppos, close_start - 1))
    ppos = close_stop + 1
    return ppos
end

local function parse(content)
    local pos, chunks = 1, {}
    while true do
        local found, err = next_tag(chunks, content, pos)
        if err then
            return nil, err
        end
        if not found then
            break
        end
        pos = found
    end
    return chunks
end

local function load_chunk(chunk_code, env)
    local fn, err = load(chunk_code, env.name, "bt", env)
    if not fn then
        return nil, parse_error(chunk_code, err)
    end
    return fn
end

--替换字符串模板
--content: 字符串模板
--env: 环境变量(包含自定义参数)
local function render(content, env)
    local chunks, err = parse(sgsub(content, "\r\n", "\n"))
    if not chunks then
        error(sformat("parse content failed: %s", err))
        return nil
    end
    local chunk = compile_chunks(chunks)
    setmetatable(env, { __index = function(t, k) return _G[k] end })
    local fn, err2 = load_chunk(chunk, env)
    if not fn then
        print(sformat("load_chunk content failed: %s", err2))
        return nil, chunk
    end
    local ok, buffer = pcall(fn)
    if ok and buffer then
        return tconcat(buffer)
    end
    print(sformat("pcall content failed: %s", buffer))
    return nil, chunk
end

--导出文件模板
--tpl_f: 文件模板
--tpl_out_f: 输出文件
--tpl_env: 环境变量
--tpl_var_f: 环境变量文件
local function render_file(tpl_f, tpl_out_f, tpl_env, tpl_var_f)
    if not tpl_f or not tpl_out_f or not tpl_env then
        error("render template file params error!")
        return
    end
    local template_file = iopen(tpl_f, "rb")
    if not template_file then
        error(sformat("open template file %s failed!", tpl_f))
        return
    end
    local content = template_file:read("*all")
    template_file:close()
    if tpl_var_f then
        setmetatable(tpl_env, { __index = function(t, k) return _G[k] end })
        local func, err = loadfile(tpl_var_f, "bt", tpl_env)
        if not func then
            error(sformat("open template variable file %s failed :%s", tpl_var_f, err))
            return
        end
        local ok, res = pcall(func)
        if not ok then
            error(sformat("load template variable file %s failed :%s", tpl_var_f, res))
            return
        end
        tpl_env.NAME = tpl_f
    end
    local out_file = iopen(tpl_out_f, "w")
    if not out_file then
        error(sformat("open template out file %s failed!", tpl_out_f))
        return
    end
    local ok, template, chunk = pcall(render, content, tpl_env)
    if not ok or not template then
        if chunk then
            out_file:write(chunk)
        end
        out_file:close()
        error(sformat("render template file %s to %s failed: %s!", tpl_f, tpl_out_f, template))
        return
    end
    out_file:write(template)
    out_file:close()
    print(sformat("render template file %s to %s success!", tpl_f, tpl_out_f))
end

--工具用法
--tpl_f: 模板文件路径
--tpl_out_f：输出文件路径
--tpl_var_f：环境变量配置文件
if select("#", ...) == 3 then
    local tpl_f, tpl_out_f, tpl_var_f = select(1, ...)
    render_file(tpl_f, tpl_out_f, {}, tpl_var_f)
end

return {
    render = render,
    render_file = render_file
}
