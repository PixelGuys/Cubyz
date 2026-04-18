const U = union(enum(u2)) {
    A: u8,
    B: u8,
    C: u8,
    D: u8,
    E: u8,
};
export fn entry() void {
    _ = U{ .E = 1 };
}

// error
//
// :6:5: error: enum tag value '4' too large for type 'u2'
