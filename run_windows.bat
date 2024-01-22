@echo off

cd /D "%~dp0"

.\debug_windows.bat -Doptimize=ReleaseFast %*
