const x = @extern(*comptime_int, .{ .name = "foo" });
const y = @extern(*fn (u8) u8, .{ .name = "bar" });
const z = @extern(*fn (u8) callconv(.c) u8, .{ .name = "bar" });
comptime {
    _ = x;
}
comptime {
    _ = y;
}
comptime {
    _ = z;
}

// error
//
// :1:19: error: extern symbol cannot have type '*comptime_int'
// :1:19: note: pointer element type 'comptime_int' is not extern compatible
// :2:19: error: extern symbol cannot have type '*fn (u8) u8'
// :2:19: note: pointer element type 'fn (u8) u8' is not extern compatible
// :2:19: note: extern function must specify calling convention
// :3:19: error: extern symbol cannot have type '*fn (u8) callconv(.c) u8'
// :3:19: note: pointer to extern function must be 'const'
