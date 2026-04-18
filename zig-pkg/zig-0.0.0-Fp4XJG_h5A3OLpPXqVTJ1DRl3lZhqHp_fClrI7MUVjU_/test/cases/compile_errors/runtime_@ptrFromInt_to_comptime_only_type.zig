const GuSettings = struct {
    fin: ?fn (c_int) callconv(.c) void,
};
pub export fn callbackFin(id: c_int, arg: ?*anyopaque) void {
    const settings: ?*GuSettings = @as(?*GuSettings, @ptrFromInt(@intFromPtr(arg)));
    if (settings.?.fin != null) {
        settings.?.fin.?(id & 0xffff);
    }
}

// error
//
// :6:19: error: cannot load comptime-only type '?fn (c_int) callconv(.c) void'
// :6:20: note: pointer of type '*?fn (c_int) callconv(.c) void' is runtime-known
