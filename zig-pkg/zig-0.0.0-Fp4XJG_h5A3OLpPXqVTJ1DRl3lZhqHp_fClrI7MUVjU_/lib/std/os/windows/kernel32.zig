const std = @import("../../std.zig");
const windows = std.os.windows;

const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const HANDLE = windows.HANDLE;
const LPCWSTR = windows.LPCWSTR;
const LPVOID = windows.LPVOID;
const LPWSTR = windows.LPWSTR;
const PROCESS = windows.PROCESS;
const THREAD_START_ROUTINE = windows.THREAD_START_ROUTINE;
const SECURITY_ATTRIBUTES = windows.SECURITY_ATTRIBUTES;
const SIZE_T = windows.SIZE_T;
const STARTUPINFOW = windows.STARTUPINFOW;

pub extern "kernel32" fn CreateProcessW(
    lpApplicationName: ?LPCWSTR,
    lpCommandLine: ?LPWSTR,
    lpProcessAttributes: ?*SECURITY_ATTRIBUTES,
    lpThreadAttributes: ?*SECURITY_ATTRIBUTES,
    bInheritHandles: BOOL,
    dwCreationFlags: windows.CreateProcessFlags,
    lpEnvironment: ?[*:0]const u16,
    lpCurrentDirectory: ?LPCWSTR,
    lpStartupInfo: *STARTUPINFOW,
    lpProcessInformation: *PROCESS.INFORMATION,
) callconv(.winapi) BOOL;
