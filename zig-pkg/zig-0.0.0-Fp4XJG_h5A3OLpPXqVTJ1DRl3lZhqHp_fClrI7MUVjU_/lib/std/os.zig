const builtin = @import("builtin");
const native_os = builtin.os.tag;

pub const linux = @import("os/linux.zig");
pub const plan9 = @import("os/plan9.zig");
pub const uefi = @import("os/uefi.zig");
pub const wasi = @import("os/wasi.zig");
pub const emscripten = @import("os/emscripten.zig");
pub const windows = @import("os/windows.zig");

test {
    _ = linux;
    if (native_os == .uefi) _ = uefi;
    _ = wasi;
    _ = windows;
}
