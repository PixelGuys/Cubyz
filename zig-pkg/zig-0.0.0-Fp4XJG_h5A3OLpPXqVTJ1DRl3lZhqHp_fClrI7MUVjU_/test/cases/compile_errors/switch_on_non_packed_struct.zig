const Auto = struct {
    a: u8,
};
export fn entry1(a: u8) void {
    const s: Auto = .{ .a = a };
    switch (s) {
        else => {},
    }
}

const Extern = extern struct {
    a: u8,
};
export fn entry2(s: Extern) void {
    switch (s) {
        else => {},
    }
}

// error
//
// :6:13: error: switch on struct with auto layout
// :1:14: note: consider 'packed struct' here
// :15:13: error: switch on struct with extern layout
// :11:23: note: consider 'packed struct' here
