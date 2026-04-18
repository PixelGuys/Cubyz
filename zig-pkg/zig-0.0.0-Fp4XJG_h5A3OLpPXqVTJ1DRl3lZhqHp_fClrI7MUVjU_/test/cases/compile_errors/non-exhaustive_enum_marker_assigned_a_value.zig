const A = enum {
    a,
    b,
    _ = 1,
};

// error
//
// :4:9: error: '_' is used to mark an enum as non-exhaustive and cannot be assigned a value
