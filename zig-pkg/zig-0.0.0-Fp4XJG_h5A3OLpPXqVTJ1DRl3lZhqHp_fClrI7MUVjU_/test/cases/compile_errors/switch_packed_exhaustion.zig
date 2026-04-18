const S = packed struct(u2) {
    a: u2,
};
export fn entry1(x: u8) void {
    const s: S = .{ .a = @intCast(x) };
    switch (s) {
        .{ .a = 0b00 }, .{ .a = 0b01 }, .{ .a = 0b10 }, .{ .a = 0b11 } => {},
        else => {},
    }
}
export fn entry2(x: u8) void {
    const s: S = .{ .a = @intCast(x) };
    switch (s) {
        .{ .a = 0b00 }, .{ .a = 0b01 }, .{ .a = 0b11 } => {},
    }
}

const U = packed union(u2) {
    a: u2,
    b: i2,
};
export fn entry3(x: u8) void {
    const u: U = .{ .a = @intCast(x) };
    switch (u) {
        .{ .a = 0b00 }, .{ .a = 0b01 }, .{ .a = 0b10 }, .{ .a = 0b11 } => {},
        else => {},
    }
}
export fn entry4(x: u8) void {
    const u: U = .{ .a = @intCast(x) };
    switch (u) {
        .{ .a = 0b00 }, .{ .a = 0b01 }, .{ .a = 0b11 } => {},
    }
}

// error
//
// :8:14: error: unreachable else prong; all cases already handled
// :13:5: error: switch must handle all possibilities
// :26:14: error: unreachable else prong; all cases already handled
// :31:5: error: switch must handle all possibilities
