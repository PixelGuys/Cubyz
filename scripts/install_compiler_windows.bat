@echo off

echo Detecting Zig compiler...

set /p baseVersion=<".zigversion"

IF "%PROCESSOR_ARCHITECTURE%"=="AMD64"	(set arch=x86_64)
IF "%PROCESSOR_ARCHITECTURE%"=="IA64"	(set arch=x86_64)
IF "%PROCESSOR_ARCHITECTURE%"=="x86"	(set arch=x86)
IF "%PROCESSOR_ARCHITECTURE%"=="ARM64"	(set arch=aarch64)
IF "%arch%"=="" (
	echo Machine architecture could not be recognized: %arch%. Please file a bug report.
	echo Defaulting architecture to x86_64.
	set arch=x86_64
)

set version=zig-%arch%-windows-%baseVersion%

if not exist compiler mkdir compiler
if not exist compiler\version.txt copy NUL compiler\version.txt >NUL

set currVersion=
set /p currVersion=<"compiler\version.txt"

if not "%version%" == "%currVersion%" (
	echo Your Zig is the wrong version.
	echo Deleting current Zig installation...
	if exist compiler\zig rmdir /s /q compiler\zig
	echo Downloading %version%...
	powershell -Command $ProgressPreference = 'SilentlyContinue'; "Invoke-WebRequest -uri https://github.com/PixelGuys/Cubyz-zig-versions/releases/download/%baseVersion%/%version%.zip -OutFile compiler\archive.zip"
	if errorlevel 1 (
		echo Failed to download the Zig compiler.
		exit /b 1
	)
	echo Extracting zip file...
	C:\Windows\System32\tar.exe -xf compiler\archive.zip --directory compiler
	ren compiler\%version% zig
	del compiler\archive.zip
	echo %version%> compiler\version.txt
	echo Done updating Zig.
) ELSE (
	echo Zig compiler is valid.
)
