const P = packed union(u8) {
    a: u8,
    b: i8,
};

export fn foo(p: P) void {
    switch (p) {
        .{ .a = 123 } => |_, tag| _ = tag,
        else => {},
    }
}

// error
//
// :8:30: error: cannot capture tag of packed union
