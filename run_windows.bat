@echo off

cd /D "%~dp0"

call debug_windows.bat -Doptimize=ReleaseFast %*

IF "%NO_PAUSE%" == "" (
	echo Press enter key to continue. (Or set NO_PAUSE=1 to skip this prompt.^)
	pause
)
