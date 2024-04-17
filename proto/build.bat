

@echo off
setlocal enabledelayedexpansion

set RootDir=%~dp0
set ProtoDir=%RootDir%\..\bin\proto\

rmdir /Q /S %ProtoDir%
md %ProtoDir%

protoc.exe --descriptor_set_out=%ProtoDir%\ncmd_cs.pb --proto_path=..\proto\ *.proto

pause

