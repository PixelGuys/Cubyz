const Small = enum(u2) {
    one,
    two,
    three,
    four,
    five,
};

const SmallUnion = union(enum(u2)) {
    one = 1,
    two,
    three,
    four,
};

comptime {
    _ = Small.one;
}
comptime {
    _ = SmallUnion.one;
}

// error
//
// :6:5: error: enum tag value '4' too large for type 'u2'
// :13:5: error: enum tag value '4' too large for type 'u2'
