set PATH=%PATH%;.\bin\lib
xcopy .\bin\lib\lstdfs.dll .\bin /s /y /e
.\bin\lua.exe .\tools\lmake\lmake.lua

pause