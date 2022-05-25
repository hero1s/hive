--main_encrypt.lua
local lstdfs     = require('lstdfs')

local ldir       = lstdfs.dir
local lmkdir     = lstdfs.mkdir
local lappend    = lstdfs.append
local lfilename  = lstdfs.filename
local lextension = lstdfs.extension
local lcurdir    = lstdfs.current_path
local sformat    = string.format
local oexec      = os.execute
local hgetenv    = os.getenv

-- 加密lua
local function encrypt(lua_dir, encrypt_dir)
    local dir_files = ldir(lua_dir)
    for _, file in pairs(dir_files) do
        local fullname = file.name
        local fname    = lfilename(fullname)
        if file.type == "directory" then
            local new_dir = lappend(encrypt_dir, fname)
            lmkdir(new_dir)
            encrypt(fullname, new_dir)
            goto continue
        end
        if lextension(fname) ~= ".lua" then
            goto continue
        end
        local luac    = lappend(lcurdir(), "../bin/luac")
        local outfile = lappend(encrypt_dir, fname)
        local luacmd  = sformat("%s -o %s %s", luac, outfile, fullname)
        oexec(luacmd)
        :: continue ::
    end
end

local input     = lcurdir()
local output    = lcurdir()
local env_input = hgetenv("HIVE_INPUT")
if not env_input or #env_input == 0 then
    print("input dir not config!")
else
    input = lappend(input, env_input)
end
local env_output = hgetenv("HIVE_OUTPUT")
if not env_output or #env_output == 0 then
    print("output dir not config!")
else
    output = lappend(output, env_output)
    lmkdir(output)
end

encrypt(input, output)

os.exit()
