@echo off

cd /D "%~dp0"

echo Detecting Zig compiler...

set /p baseVersion=<".zig-version"


ARM64 (arm)

AMD64
IA64

X86 (32 bit)

IF "%PROCESSOR_ARCHITECTURE%"=="AMD64"	(set arch=x86_64)
IF "%PROCESSOR_ARCHITECTURE%"=="IA64"	(set arch=x86_64)
IF "%PROCESSOR_ARCHITECTURE%"=="x64"	(set arch=x86)
IF "%PROCESSOR_ARCHITECTURE%"=="ARM64"	(set arch=aarch64)
IF "%arch%"=="" (
	echo Machine architecture could not be determined. Please file a bug report.
)

set version=zig-windows-%arch%-%baseVersion%

if not exist compiler mkdir compiler
if not exist compiler\version.txt copy NUL compiler\version.txt >NUL

set currVersion=
set /p currVersion=<"compiler\version.txt"

if not "%version%" == "%currVersion%" (
	echo Your Zig is the wrong version.
	echo Deleting current Zig installation ...
	if exist compiler\zig rmdir /s /q compiler\zig
	echo Downloading %version% ...
	powershell -Command $ProgressPreference = 'SilentlyContinue'; "Invoke-WebRequest -uri https://ziglang.org/builds/%version%.zip -OutFile compiler\archive.zip"
	if errorlevel 1 (
		echo Failed to download the Zig compiler.
		echo Press any key to continue.
		pause
		exit /b 1
	)
	echo Extracting zip file ...
	powershell $ProgressPreference = 'SilentlyContinue'; Expand-Archive compiler\archive.zip -DestinationPath compiler
	ren compiler\%version% zig
	del compiler\archive.zip
	echo %version%> compiler\version.txt
	echo Done updating Zig.
) ELSE (
	echo Zig compiler is valid.
)

echo Building Zig Cubyz (%*) from source. This may take a few minutes...

compiler\zig\zig build %*

if errorlevel 1 (
	echo Failed to build Cubyz.
	echo Press any key to continue.
	pause
	exit /b 1
)

echo Cubyz successfully built!
echo Launching Cubyz.

compiler\zig\zig build run %*
