#pragma once

static const char* g_sandbox = u8R"__(
--sandbox.lua
local logger      = require("lualog")
local lstdfs      = require("lstdfs")

local pairs       = pairs
local loadfile    = loadfile
local iopen       = io.open
local mabs        = math.abs
local tinsert     = table.insert
local tsort       = table.sort
local sformat     = string.format
local sfind       = string.find
local dtraceback  = debug.traceback
local file_time   = lstdfs.last_write_time
local ldir        = lstdfs.dir
local lfilename   = lstdfs.filename
local lextension  = lstdfs.extension
local is_dir      = lstdfs.is_directory
local log_info    = logger.warn
local log_err     = logger.error

local load_files  = {}
local load_codes  = {}
local search_path = {}

local TITLE       = hive.title
local log_error = function(content)
    log_err(content, TITLE, FEATURE)
end
local log_output = function(content)
    log_info(content, TITLE)
end

local function ssplit(str, token)
    local t = {}
    while #str > 0 do
        local pos = str:find(token)
        if pos then
            t[#t + 1] = str:sub(1, pos - 1)
            str       = str:sub(pos + 1, #str)
        else
            t[#t + 1] = str
            break
        end
    end
    return t
end

--加载lua文件搜索路径
for _, path in ipairs(ssplit(package.path, ";")) do
    search_path[#search_path + 1] = path:sub(1, path:find("?") - 1)
end

local function can_reload(fullpath)
    if sfind(fullpath, "/hive/script/basic") then
        return false
    end
    return true
end

local function search_load(node)
    local load_path = node.fullpath
    if load_path then
        node.time = file_time(load_path)
        return loadfile(load_path)
    end
    local filename = node.filename
    for _, path_root in pairs(search_path) do
        local fullpath = path_root .. filename
        local file     = iopen(fullpath)
        if file then
            file:close()
            node.fullpath   = fullpath
            node.time       = file_time(fullpath)
            node.can_reload = can_reload(fullpath)
            return loadfile(fullpath)
        end
    end
    return nil, "file not exist!"
end

local function try_load(node, reload)
    local trunk_func, err = search_load(node)
    if not trunk_func then
        log_error(sformat("[sandbox][try_load] load file: %s ... [failed]\nerror : %s", node.filename, err))
        return
    end
    local ok, res = xpcall(trunk_func, dtraceback)
    if not ok then
        log_error(sformat("[sandbox][try_load] exec file: %s ... [failed]\nerror : %s", node.filename, res))
        return
    end
    if res then
        node.res = res
    end
    if reload then
        log_output(sformat("[sandbox][try_load] reload file: %s ... [ok]", node.filename))
    end
    return res
end

function import(filename)
    local node = load_codes[filename]
    if not node then
        node                 = { filename = filename }
        load_codes[filename] = node
        tinsert(load_files,node)
    end
    if not node.time then
        try_load(node)
    end
    return node.res
end

--导入目录注意不能有依赖关系
function import_dir(dir)
    for _, path_root in pairs(search_path) do
        local fullpath = path_root .. dir
        if is_dir(fullpath) then
            local dir_files = ldir(fullpath)
            local tmp_files = {}
            for _, file in pairs(dir_files) do
                local fullname = file.name
                local fname    = lfilename(fullname)
                if file.type ~= "directory" and lextension(fname) == ".lua" then
                    tmp_files[#tmp_files + 1] = fname
                end
            end
            --排序方便对比
            tsort(tmp_files, function(a, b)
                return a < b
            end)
            for _, fname in pairs(tmp_files) do
                local filename = dir .. "/" .. fname
                import(filename)
            end
        end
    end
end

--加载的文件时间
function hive.import_file_time(filename)
    local node = load_codes[filename]
    if not node or not node.time then
        return 0
    end
    return node.time
end
--加载的文件路径
function hive.import_file_dir(filename)
    local node = load_codes[filename]
    if not node or not node.fullpath then
        return nil
    end
    return lstdfs.parent_path(node.fullpath)
end

function hive.reload()
    local count = 0
    for _, node in ipairs(load_files) do
        if node.can_reload then
            local filetime, err = file_time(node.fullpath)
            if filetime == 0 then
                log_error(sformat("[hive][reload] %s get_time failed(%s)", node.fullpath, err))
                goto continue
            end
            if node.time then
                if mabs(node.time - filetime) > 1 then
                    try_load(node, true)
                    count = count + 1
                end
            else
                log_error(sformat("[hive][reload] error file:%s", node.filename))
            end
        end
        :: continue ::
    end
    return count
end
)__";