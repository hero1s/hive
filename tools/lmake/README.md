# lmake

# 概述
基于lua的跨平台C/C++项目编译模板框架！

# 依赖
- [lua](https://github.com/xiyoo0812/lua.git)5.4
- [lstdfs](https://github.com/xiyoo0812/lstdfs.git), 一个基于C++17的文件系统库
- [ltemplate](https://github.com/xiyoo0812/ltemplate.git), 一个基于lua的文件模板生成库

# 机制
- 使用lstdfs遍历项目文件
- 在tmpl子目录下配置windows/linux/macos三个主流平台的工程模板文件
- 使用ltemplate自动扫描配置文件生成项目文件(makefile/vcxproj)

# 配置
- lmake文件: 工程根目录需要配置此文件
```lua
--lmake
--工程名
SOLUTION = "xxxx"
--lmake目录
LMAKE_DIR = "../lmake"
--mimalloc
USE_MIMALLOC = false
```
- *.lmak：子项目配置文件, 此文件需要配置项目细节
- share.lua: lmake公共配置文件, 以及参考说明, 此文件内包含lmake所有的默认选项

# 生成文件
- Makefile: 在工程根目录自动生成, 用于一键编译linux/macos项目
- *.mak: 在子项目目录自动生成, 用于编译linux/macos子项目
- *.sln: 在工程根目录自动生成, windows下visual studio的工程文件
- *.vcxproj : 在子项目目录自动生成, 用于管理vs2019子项目
- *.vcxproj.filters : 在子项目目录自动生成, 用于管理vs2019子项目目录结构

# 配置说明
- 参考share.lua
- 配置文件使用lua语法
- 标准库版本
```lua
--C标准库版本, 默认gnu99
--gnu99/gnu11/gnu17
STDC = "gnu99"
--C++标准库版本, 默认C++14
--c++11/c++14/c++17/c++20
STDCPP = "c++14"
```
- GCC编译选项
```lua
FLAGS = {
	"Wno-sign-compare"
}
```
- include目录(-I)
```lua
--各个平台都需要的include目录定义
INCLUDES = {
}
--LINUX需要的include目录
LINUX_INCLUDES = {
}
--DARWIN需要的include目录
DARWIN_INCLUDES = {
}
--WINDOWS需要include目录
WINDOWS_INCLUDES = {
}
```
- 编译符号定义(-D)
```lua
--需要定义的选项
DEFINES = {
	"MAKE_LUA"
}
--LINUX需要定义的选项
LINUX_DEFINES = {
}
--DARWIN需要定义的选项
DARWIN_DEFINES = {
}
--WINDOWS需要定义的选项
WINDOWS_DEFINES = {
}
```
- 链接库目录(-L)
```lua
--需要附加link库目录
LIBRARY_DIR = {
}
--WINDOWS需要附加link库目录
WINDOWS_LIBRARY_DIR = {
}
--LINUX需要附加link库目录
LINUX_LIBRARY_DIR = {
}
--DARWIN需要附加link库目录
DARWIN_LIBRARY_DIR = {
}
```
- 需要连接的库(-l)
```lua
--需要连接的库文件
--不需要带后缀, windows会自动加上.lib后缀
LIBS = {
    "lua"
}
--WINDOWS需要连接的库文件
--windows可能会使用.a文件, 因此此处需要使用全名
WINDOWS_LIBS = {
    "libcurl.a",
	"ws2_32.lib"
}
--LINUX需要连接的库文件
LINUX_LIBS = {
}
--DARWIN需要连接的库文件
DARWIN_LIBS = {
}
```
- 源文件目录
```lua
--定义项目源文件的路径
--不配置默认项目目录下的src
--如果没有配置OBJS，则会自动扫描SRC_DIR下的所有符合条件的文件作为目标
--不会递归扫描，多目录使用SUB_DIR
SRC_DIR = "lua"
```
- 目标文件目录
```lua
--目标文件生成路径
--.so/.exe/.dll
DST_DIR = "bin"

--LIB文件生成路径
--.a/.lib
DST_LIB_DIR = "library"
```
- 子目录定义
```lua
--子目录路径，目录基于SRC_DIR
--主要用于项目源文件分布在多个目录
SUB_DIR = {
	"zlib",
	"minizip",
	"tinyxml2",
}
--自动搜索子目录
AUTO_SUB_DIR = false
```
- 目标文件定义
```lua
--用于指定目标文件，配置后不会自动扫描生成目标
--目标文件基于SRC_DIR
OBJS = {
	"onelua.c"
}
```
- 需要排除编译的文件
```lua
--需要排除的源文件, 目录基于SRC_DIR
EXCLUDE_FILE = {
	"minizip/minizip.c",
	"minizip/miniunz.c",
}
```
- 目标文件前缀
```lua
--linux/macos适用
--配置之后，linux/macos生成的lib/so文件会加上lib前缀
LIB_PREFIX = 1
LIB_PREFIX = nil
```
- WINDOWS预编译命令
```lua
--格式: { cmd, args }
WINDOWS_PREBUILDS = {
	{ "copy /y", "bin/libcurl-x64.dll $(SolutionDir)bin" }
}
```
- NWINDOWS预编译命令
```lua
--格式: { cmd, args }
NWINDOWS_PREBUILDS = {
	{ "copy /y", "bin/libcurl-x64.dll $(SolutionDir)bin" }
}
```
- WINDOWS编译后命令
```lua
--格式: { cmd, args }
WINDOWS_POSTBUILDS = {
    { "cp -r", "bin/libcurl-x64.dll $(SolutionDir)bin" }
}
```
- 非WINDOWS编译后命令
```lua
--格式: { cmd, args }
NWINDOWS_POSTBUILDS = {
    { "cp -r", "bin/libcurl-x64.dll $(SolutionDir)bin" }
}
```
- 依赖项目
```lua
--用于确定编译顺序
DEPS = {
    "lua"
}
```
- MIMALLOC库目录
```lua
--是否启用mimalloc库
MIMALLOC_DIR = "extend/mimalloc/mimalloc/include"
```
- 分组定义
```lua
--用于生成Makefile的标签以及sln的文件夹
GROUP = "proj"
```