@echo off

set version=zig-windows-x86_64-0.12.0-dev.983+78f2ae7f2

if not exist compiler mkdir compiler
if not exist compiler\version.txt copy NUL compiler\version.txt >NUL

set currVersion=
set /p currVersion=<"compiler\version.txt"

if not "%version%" == "%currVersion%" (
    echo Deleting old zig installation ...
	if exist compiler\zig rmdir /s /q compiler\zig
    echo Downloading zig version %version% ...
    powershell -Command $ProgressPreference = 'SilentlyContinue'; "Invoke-WebRequest -uri https://ziglang.org/builds/%version%.zip -OutFile compiler\archive.zip"
    echo Extracting zip file ...
    powershell $ProgressPreference = 'SilentlyContinue'; Expand-Archive compiler\archive.zip -DestinationPath compiler
	ren compiler\%version% zig
    echo Done.
    del compiler\archive.zip
    echo %version%> compiler\version.txt
)

compiler\zig\zig build run %*