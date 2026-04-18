const U = union(enum(i2)) {
    A: u8,
    B: u8,
    C: u8,
    D: u8,
};
export fn entry() void {
    _ = U{ .D = 1 };
}

// error
//
// :4:5: error: enum tag value '2' too large for type 'i2'
