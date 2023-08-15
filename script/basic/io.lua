local strbyte = string.byte
local strsub  = string.sub
local strlen  = string.len

io_ext        = _ENV.io_ext or {}

--
-- Write content to a new file.
--
function io_ext.writefile(filename, content)
    local file = io.open(filename, "w+b")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

--
-- Read content from new file.
--
function io_ext.readfile(filename)
    local file, err = io.open(filename, "rb")
    if file then
        local content = file:read("*a")
        file:close()
        return content
    end
    return false, err
end

--1.获取指定文件的指定行内容，若未指定行数，返回 {文件内容列表，文件总行数}
--2.若行数在文件总行数范围，返回 {文件内容列表，文件总行数，指定行数的内容}
--3.若行数超出文件总行数，返回 {文件内容列表，文件总行数}
--4.filePath：文件路径，rowNumber：指定行数
function io_ext.read_text_row(filePath, rowNumber)
    local openFile = io.open(filePath, "r")
    assert(openFile, "read file is nil")
    local reTable = {}
    local reIndex = 0
    for r in openFile:lines() do
        reIndex          = reIndex + 1
        reTable[reIndex] = r
    end
    io.close(openFile)
    if rowNumber ~= nil and reIndex > rowNumber then
        return reTable, reIndex, reTable[rowNumber]
    else
        return reTable, reIndex
    end
end

function io_ext.pathinfo(path)
    local pos    = strlen(path)
    local extpos = pos + 1
    while pos > 0 do
        local b = strbyte(path, pos)
        if b == 46 then
            -- 46 = char "."
            extpos = pos
        elseif b == 47 then
            -- 47 = char "/"
            break
        end
        pos = pos - 1
    end

    local dirname  = strsub(path, 1, pos)
    local filename = strsub(path, pos + 1)

    extpos         = extpos - pos
    local basename = strsub(filename, 1, extpos - 1)
    local extname  = strsub(filename, extpos)

    return {
        dirname  = dirname,
        filename = filename,
        basename = basename,
        extname  = extname
    }
end