--stdfs_test.lua
local lstdfs   = require("lstdfs")

local log_info = logger.info
local sformat  = string.format

local work_dir = lstdfs.current_path()
local ltype    = lstdfs.filetype(work_dir)
log_info("current_path: {}, type: {}", work_dir, ltype)

local root_name = lstdfs.root_name(work_dir)
local root_path = lstdfs.root_path(work_dir)
log_info("root_name: {}, root_path: {}", root_name, root_path)

local parent_path   = lstdfs.parent_path(work_dir)
local relative_path = lstdfs.relative_path(work_dir)
log_info("parent_path: {}, relative_path: {}", parent_path, relative_path)

local cur_dirs = lstdfs.dir(work_dir)
for _, file in pairs(cur_dirs) do
    log_info("cur dir -> filename: {}, filetype: {}", file.name, file.type)
end

local recursive_dirs = lstdfs.dir(work_dir, true)
for _, file in pairs(recursive_dirs) do
    log_info("recursive dir -> filename: {}, filetype: {}", file.name, file.type)
end

local mok, merr = lstdfs.mkdir("logs/a/b/c")
log_info("mkdir -> ok: {}, err: {}", mok, merr)

local cok, cerr = lstdfs.chdir("logs")
local new_dir   = lstdfs.current_path()
local is_dir    = lstdfs.is_directory(new_dir)
log_info("chdir -> ok: {}, err: {}", cok, cerr)
log_info("chdir -> new_dir: {}, is_dir: {}", new_dir, is_dir)

local absolute1 = lstdfs.is_absolute(new_dir)
local absolute2 = lstdfs.is_absolute(relative_path)
log_info("is_absolute -> absolute1: {}, absolute:{}", absolute1, absolute2)

local exista   = lstdfs.exists("a")
local existb   = lstdfs.exists("b")
local temp_dir = lstdfs.temp_dir()
log_info("exists -> exista: {}, existb: {}, temp_dir:{}", exista, existb, temp_dir)

local splits = lstdfs.split(new_dir)
for _, node in pairs(splits) do
    log_info("split dir -> node: {}", node)
end

local rok, rerr = lstdfs.remove("c")
log_info("remove1 -> rok: {}, rerr: {}", rok, rerr)

local nok, nerr = lstdfs.rename("a", "b")
log_info("rename -> nok:{}, nerr:{}", nok, nerr)

local rbok, rberr = lstdfs.remove("b")
local raok, raerr = lstdfs.remove("b", true)
log_info("remove2 -> rbok: {}, rberr: {}, raok:{}, raerr:{}", rbok, rberr, raok, raerr)

local cfok, cferr   = lstdfs.copy_file("test/test-2-20210820-235824.123.p11456.log", "test-2-20210820-235824.123.p11456.log")
local cfok2, cferr2 = lstdfs.copy_file("test/test-2-20210821-000053.361.p7624.log", "../")
log_info("copy_file -> cfok:{}, cferr:{}, cfok2:{}, cferr2:{}", cfok, cferr, cfok2, cferr2)

local cok1, cerr1 = lstdfs.copy("test", "test2")
local cok2, cerr2 = lstdfs.remove("test2", true)
log_info("copy_file -> cok:{}, cerr:{}, cok2:{}, cerr2:{}", cok1, cerr1, cok2, cerr2)

local n2ok, n2err = lstdfs.rename("test-2-20210820-235824.123.p11456.log", "tttt.log")
log_info("rename2 -> n2ok:{}, n2err:{}", n2ok, n2err)

local absolute  = lstdfs.absolute("tttt.log")
local filename  = lstdfs.filename(absolute)
local extension = lstdfs.extension(absolute)
local stem      = lstdfs.stem(absolute)
log_info("info -> absolute:{}, extension:{}, filename:{}, stem:{}", absolute, extension, filename, stem)

local afile  = lstdfs.append(absolute, "d.log")
local apath  = lstdfs.append(absolute, "dc")
local afpath = lstdfs.append(afile, "ff")
local concat = lstdfs.concat("apath", "ff.png")
log_info("append -> afile: {}, apath: {}, afpath: {}, concat: {}", afile, apath, afpath, concat)

local time, terr = lstdfs.last_write_time(absolute)
local extension2 = lstdfs.replace_extension(absolute, "log2")
local filename2  = lstdfs.replace_filename(absolute, "ffff.log")
local newname    = lstdfs.remove_filename(absolute)
log_info("info -> time:{}, terr:{}, extension2:{}, filename2:{}, newname:{}", time, terr, extension2, filename2, newname)

local rfok, rferr = lstdfs.remove("tttt.log")
log_info("remove3 -> rfok: {}, rferr: {}", rfok, rferr)
