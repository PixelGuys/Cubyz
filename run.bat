@echo off

set version=zig-windows-x86_64-0.12.0-dev.706+62a0fbdae

if not exist "./compiler" mkdir "./compiler"
if not exist "./compiler/zig" mkdir "./compiler/zig"
if not exist "./compiler/version.txt" copy NUL "./compiler/version.txt"

set /p curVersion=<"./compiler/version.txt"

if not "%version%" == "%curVersion%" (
	echo "Deleting old zig installation..."
	rmdir /s /q "./compiler/zig"
	mkdir "./compiler/zig"
	echo "Downloading %version%..."
	powershell -Command "Invoke-WebRequest -uri https://ziglang.org/builds/%version%.zip -OutFile ./compiler/archive.zip"
	echo "Extracting zip file..."
	powershell Expand-Archive ".\compiler\archive.zip" -DestinationPath ".\compiler\zig"
	echo "Done."
	del ./compiler/archive.zip
	echo %version%> "./compiler/version.txt"
)

./compiler/zig/zig build run %*