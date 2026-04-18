const E = enum {
    a,
    b,
    c,
};

const U = union(E) {
    a: i32,
    b: f64,
};

export fn entry() usize {
    return @sizeOf(U);
}

// error
//
// :7:11: error: enum field 'c' missing from union
// :4:5: note: enum field here
