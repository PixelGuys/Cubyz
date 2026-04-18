const std = @import("std");
const builtin = @import("builtin");
const w = std.os.windows;

pub fn main() !void {
    if (builtin.os.tag == .windows) {
        const name = std.unicode.wtf8ToWtf16LeStringLiteral("FOO");
        const RT_RCDATA = MAKEINTRESOURCEW(10);
        const handle = FindResourceW(null, name, RT_RCDATA) orelse {
            std.debug.print("unable to find resource: {t}\n", .{w.GetLastError()});
            return error.FailedToLoadResource;
        };
        const res = LoadResource(null, handle) orelse {
            std.debug.print("unable to load resource: {t}\n", .{w.GetLastError()});
            return error.FailedToLoadResource;
        };
        const data_ptr = LockResource(res) orelse {
            std.debug.print("unable to lock resource: {t}\n", .{w.GetLastError()});
            return error.FailedToLoadResource;
        };
        const size = SizeofResource(null, handle);
        const data = @as([*]const u8, @ptrCast(data_ptr))[0..size];
        try std.testing.expectEqualSlices(u8, "foo", data);
    }
}

const HRSRC = *opaque {};
const HGLOBAL = *opaque {};
fn MAKEINTRESOURCEW(id: u16) [*:0]align(1) const w.WCHAR {
    return @ptrFromInt(id);
}

extern "kernel32" fn FindResourceW(
    hModule: ?w.HMODULE,
    lpName: [*:0]align(1) const w.WCHAR,
    lpType: [*:0]align(1) const w.WCHAR,
) callconv(.winapi) ?HRSRC;

extern "kernel32" fn LoadResource(
    hModule: ?w.HMODULE,
    hResInfo: HRSRC,
) callconv(.winapi) ?HGLOBAL;

extern "kernel32" fn LockResource(
    hResData: HGLOBAL,
) callconv(.winapi) ?w.LPVOID;

extern "kernel32" fn SizeofResource(
    hModule: ?w.HMODULE,
    hResInfo: HRSRC,
) callconv(.winapi) w.DWORD;
