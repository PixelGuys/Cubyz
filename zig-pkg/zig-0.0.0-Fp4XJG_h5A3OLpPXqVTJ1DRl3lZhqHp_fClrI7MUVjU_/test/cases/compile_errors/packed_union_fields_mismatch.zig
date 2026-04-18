export fn entry1() void {
    const U = packed union {
        a: u1,
        b: u2,
    };
    _ = @as(U, undefined);
}

// error
//
// :4:12: error: field bit width does not match earlier field
// :4:12: note: field type 'u2' has bit width '2'
// :3:12: note: other field type 'u1' has bit width '1'
// :4:12: note: all fields in a packed union must have the same bit width
