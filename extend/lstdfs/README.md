# lstdfs
A Lua File Syetem Library  Base on std c++17 ！

# 依赖
- c++17
- [lua](https://github.com/xiyoo0812/lua.git)5.2以上
- 项目路径如下<br>
  |--proj <br>
  &emsp;|--lua <br>
  &emsp;|--lstdfs

  # 编译
- msvc : 准备好lua依赖库并放到指定位置，将proj文件加到sln后编译。
- linux：准备好lua依赖库并放到指定位置，执行make -f lstdfs.mak

# 功能
- dir
- stem
- copy
- mkdir
- chdir
- split
- rename
- exists
- remove
- temp_dir
- absolute
- filetype
- filename
- copy_file
- extension
- root_name
- root_path
- is_absolute
- copy_option
- parent_path
- is_directory
- current_path
- relative_path
- last_write_time
- remove_filename
- replace_filename
- replace_extension

# lua使用方法
```lua
--stdfs_test.lua
local lstdfs    = require("lstdfs")

local log_info  = logger.info
local sformat   = string.format

local work_dir = lstdfs.current_path()
local ltype = lstdfs.filetype(work_dir)
log_info(sformat("current_path: %s, type: %s", work_dir, ltype))
local root_name = lstdfs.root_name(work_dir) 
local root_path = lstdfs.root_path(work_dir) 
log_info(sformat("root_name: %s, root_path: %s", root_name, root_path))
local parent_path = lstdfs.parent_path(work_dir) 
local relative_path = lstdfs.relative_path(work_dir) 
log_info(sformat("parent_path: %s, relative_path: %s", parent_path, relative_path))
local cur_dirs = lstdfs.dir(work_dir)
for _, file in pairs(cur_dirs) do
    log_info(sformat("cur dir -> filename: %s, filetype: %s", file.name, file.type))
end
local recursive_dirs = lstdfs.dir(work_dir, true)
for _, file in pairs(recursive_dirs) do
    log_info(sformat("recursive dir -> filename: %s, filetype: %s", file.name, file.type))
end
local mok, merr = lstdfs.mkdir("logs/a/b/c")
log_info(sformat("mkdir -> ok: %s, err: %s", mok, merr))
local cok, cerr = lstdfs.chdir("logs")
local new_dir = lstdfs.current_path()
local is_dir = lstdfs.is_directory(new_dir)
log_info(sformat("chdir -> ok: %s, err: %s", cok, cerr))
log_info(sformat("chdir -> new_dir: %s, is_dir: %s", new_dir, is_dir))
local absolute1 = lstdfs.is_absolute(new_dir)
local absolute2 = lstdfs.is_absolute(relative_path)
log_info(sformat("is_absolute -> absolute1: %s, absolute:%s", absolute1, absolute2))
local exista = lstdfs.exists("a")
local existb = lstdfs.exists("b")
local temp_dir = lstdfs.temp_dir()
log_info(sformat("exists -> exista: %s, existb: %s, temp_dir:%s", exista, existb, temp_dir))
local splits = lstdfs.split(new_dir)
for _, node in pairs(splits) do
    log_info(sformat("split dir -> node: %s", node))
end
local rok, rerr = lstdfs.remove("c")
log_info(sformat("remove1 -> rok: %s, rerr: %s", rok, rerr))
local nok, nerr = lstdfs.rename("a", "b")
log_info(sformat("rename -> nok:%s, nerr:%s", nok, nerr))
local rbok, rberr = lstdfs.remove("b")
local raok, raerr = lstdfs.remove("b", true)
log_info(sformat("remove2 -> rbok: %s, rberr: %s, raok:%s, raerr:%s", rbok, rberr, raok, raerr))
local cfok, cferr = lstdfs.copy_file("test/test-2-20210820-235824.123.p11456.log", "test-2-20210820-235824.123.p11456.log")
local cfok2, cferr2 = lstdfs.copy_file("test/test-2-20210821-000053.361.p7624.log", "../")
log_info(sformat("copy_file -> cfok:%s, cferr:%s, cfok2:%s, cferr2:%s", cfok, cferr, cfok2, cferr2))
local cok, cerr = lstdfs.copy("test", "test2")
local cok2, cerr2 = lstdfs.remove("test2", true)
log_info(sformat("copy_file -> cok:%s, cerr:%s, cok2:%s, cerr2:%s", cok, cerr, cok2, cerr2))
local n2ok, n2err = lstdfs.rename("test-2-20210820-235824.123.p11456.log", "tttt.log")
log_info(sformat("rename2 -> n2ok:%s, n2err:%s", n2ok, n2err))
local absolute = lstdfs.absolute("tttt.log")
local filename = lstdfs.filename(absolute)
local extension = lstdfs.extension(absolute)
local stem = lstdfs.stem(absolute)
log_info(sformat("info -> absolute:%s, extension:%s, filename:%s, stem:%s", absolute, extension, filename, stem))
local time = lstdfs.last_write_time(absolute)
local extension2 = lstdfs.replace_extension(absolute, "log2")
local filename2 = lstdfs.replace_filename(absolute, "ffff.log")
local newname = lstdfs.remove_filename(absolute)
log_info(sformat("info -> time:%s, extension2:%s, filename2:%s, newname:%s", time, extension2, filename2, newname))
local rfok, rferr = lstdfs.remove("tttt.log")
log_info(sformat("remove3 -> rfok: %s, rferr: %s", rfok, rferr))

```