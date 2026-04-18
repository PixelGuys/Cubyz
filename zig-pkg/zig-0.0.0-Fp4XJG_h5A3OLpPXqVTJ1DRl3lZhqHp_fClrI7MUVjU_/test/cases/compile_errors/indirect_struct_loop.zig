const A = struct {
    b: B,
};
const B = struct {
    c: C,
};
const C = struct {
    a: A,
};
export fn entry() usize {
    return @sizeOf(A);
}

// error
//
// error: dependency loop with length 3
// :2:8: note: type 'tmp.A' depends on type 'tmp.B' for field declared here
// :5:8: note: type 'tmp.B' depends on type 'tmp.C' for field declared here
// :8:8: note: type 'tmp.C' depends on type 'tmp.A' for field declared here
// note: eliminate any one of these dependencies to break the loop
