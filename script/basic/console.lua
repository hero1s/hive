--trace.lua
local llog          = require("lualog")
local load          = load
local pcall         = pcall
local stdout        = io.stdout
local ssub          = string.sub
local schar         = string.char
local sformat       = string.format
local tpack         = table.pack
local tconcat       = table.concat

--
local console_buf   = ""
local console_input = false

local function exec_command(cmd)
    stdout:write("\ncommand: " .. cmd .. "\n")
    local res = tpack(pcall(load(sformat("return %s", cmd))))
    if res[1] then
        stdout:write("result: " .. tconcat(res, ",", 2, #res))
    else
        stdout:write("error: " .. tconcat(res, ",", 2, #res))
    end
end

hive.console = function(ch)
    if console_input then
        local sch = schar(ch)
        if ch ~= 13 and ch ~= 8 then
            stdout:write(sch)
            console_buf = console_buf .. sch
        end
        if ch == 8 then
            if #console_buf > 0 then
                stdout:write(sch)
                stdout:write(schar(32))
                stdout:write(sch)
                console_buf = ssub(console_buf, 1, #console_buf - 1)
            end
        end
        if ch == 13 or #console_buf > 255 then
            llog.daemon(false)
            if #console_buf > 0 then
                exec_command(console_buf)
            end
            stdout:write("\n")
            console_input = false
            console_buf   = ""
        end
    else
        if ch == 13 then
            console_input = true
            llog.daemon(true)
            stdout:write("input> ")
        end
    end
end