const Letter = enum {
    A,
    B,
    C,
};
const Payload = union(Letter) {
    A: i32,
    B: f64,
};
export fn entry() usize {
    return @sizeOf(Payload);
}

// error
//
// :6:17: error: enum field 'C' missing from union
// :4:5: note: enum field here
