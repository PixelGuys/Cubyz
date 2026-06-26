@echo off
setlocal enabledelayedexpansion

for %%i in (*.ogg) do (
    set "output=%%~ni.ogg"
    ffmpeg -i "%%i" -c:a libvorbis -q:a 3 "newaud/!output!"
)

pause