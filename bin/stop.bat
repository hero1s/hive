@echo off

taskkill -f -im "hive.exe"

ping -n 2 127.0.0.1>nul
