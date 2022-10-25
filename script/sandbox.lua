--sandbox.lua
local llog        = require("lualog")
local lstdfs      = require("lstdfs")

local pairs       = pairs
local loadfile    = loadfile
local iopen       = io.open
local mabs        = math.abs
local tpack       = table.pack
local tunpack     = table.unpack
local tsort       = table.sort
local sformat     = string.format
local sfind       = string.find
local dgetinfo    = debug.getinfo
local file_time   = lstdfs.last_write_time
local ldir        = lstdfs.dir
local lfilename   = lstdfs.filename
local lextension  = lstdfs.extension
local is_dir      = lstdfs.is_directory

local load_files  = {}
local search_path = {}

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
    if sfind(fullpath, "/hive/script/") then
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
        llog.error(sformat("[sandbox][try_load] load file: %s ... [failed]\nerror : %s", node.filename, err))
        return
    end
    local res = tpack(pcall(trunk_func))
    if not res[1] then
        llog.error(sformat("[sandbox][try_load] exec file: %s ... [failed]\nerror : %s", node.filename, res[2]))
        return
    end
    if reload then
        llog.info(sformat("[sandbox][try_load] load file: %s ... [ok]", node.filename))
    end
    return tunpack(res, 2)
end

function import(filename)
    local node = load_files[filename]
    if not node then
        node                 = { filename = filename }
        load_files[filename] = node
    end
    if not node.time then
        local res = try_load(node)
        if res then
            node.res = res
        end
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
    local node = load_files[filename]
    if not node or not node.time then
        return 0
    end
    return node.time
end
--加载的文件路径
function hive.import_file_dir(filename)
    local node = load_files[filename]
    if not node or not node.fullpath then
        return nil
    end
    return lstdfs.parent_path(node.fullpath)
end

function hive.reload()
    local count = 0
    for path, node in pairs(load_files) do
        if node.can_reload then
            local filetime = file_time(node.fullpath)
            if node.time then
                if mabs(node.time - filetime) > 3 then
                    local res = try_load(node, true)
                    if res then
                        node.res = res
                    end
                    count = count + 1
                end
                if count > 20 then
                    return count
                end
            else
                llog.error(sformat("[hive][reload] error file:%s", node.filename))
            end
        end
    end
    return count
end

function hive.load(name)
    return hive[name]
end

function hive.get(name)
    local global_obj = hive[name]
    if not global_obj then
        local info = dgetinfo(2, "S")
        llog.error(sformat("[hive][get] %s not initial! source(%s:%s)", name, info.short_src, info.linedefined))
        return
    end
    return global_obj
end
