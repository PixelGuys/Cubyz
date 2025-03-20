@echo off
setlocal enabledelayedexpansion

"compiler/zig/zig.exe" build fmt -- "src/zon.zig"

set "pattern=*.zig"

for /r src %%f in (%pattern%) do (
    "zig-out/bin/zig_fmt.exe" %%f
)

set "pattern=*.zon"

for /r assets %%f in (%pattern%) do (
    "zig-out/bin/zig_fmt.exe" %%f
)

endlocal
