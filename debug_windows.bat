@echo off

cd /D "%~dp0"

call scripts\install_compiler_windows.bat
if errorlevel 1 (
	echo Failed to install Zig compiler.
	exit /b 1
)

echo Building Zig Cubyz (%*^) from source. This may take a few minutes...

compiler\zig\zig build --error-style minimal %*

if errorlevel 1 (
	exit /b 1
)

echo Cubyz successfully built!
echo Launching Cubyz.

zig-out\bin\Cubyz
