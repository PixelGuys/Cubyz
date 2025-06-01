@echo off

cd /D "%~dp0"

call scripts\detect_compiler_windows.bat
if errorlevel 1 (
	echo Failed to detect Zig compiler.
	exit /b 1
)

echo Building Zig Cubyz (%*^) from source. This may take a few minutes...

compiler\zig\zig build %*

if errorlevel 1 (
	exit /b 1
)

echo Cubyz successfully built!
echo Launching Cubyz.

zig-out\bin\Cubyzig
