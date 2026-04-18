const U = union(enum(comptime_int)) { a: u32 };
comptime {
    const u: U = .{ .a = 123 };
    _ = u;
}

// error
//
// :1:22: error: expected integer tag type, found 'comptime_int'
