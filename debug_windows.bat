@echo off

echo "Detecting Zig compiler..."

set /p baseVersion=<".zig-version"
set version=zig-windows-x86_64-%baseVersion%

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
        echo "Failed to download the Zig compiler."
        echo "Press any key to continue."
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
    echo "Zig compiler is valid."
)

echo "Building Cubyzig from source. This may take up to 10 minutes..."

compiler\zig\zig build %*

if errorlevel 1 (
    echo "Failed to build Cubyz."
    echo "Press any key to continue."
    pause
    exit /b 1
)

compiler\zig\zig run %*
