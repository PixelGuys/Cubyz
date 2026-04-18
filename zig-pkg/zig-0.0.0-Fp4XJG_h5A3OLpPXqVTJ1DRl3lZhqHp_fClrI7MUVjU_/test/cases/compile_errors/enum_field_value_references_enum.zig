pub const Foo = enum(c_int) {
    a = 10,
    b = @intFromEnum(Foo.a) - 1,
};
export fn entry() void {
    _ = @as(Foo, .a);
}

// error
//
// :3:25: error: type 'tmp.Foo' depends on itself for field usage here
