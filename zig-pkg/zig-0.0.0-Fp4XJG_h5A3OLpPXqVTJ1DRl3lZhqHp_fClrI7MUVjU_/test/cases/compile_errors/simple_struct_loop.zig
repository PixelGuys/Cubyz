const A = struct {
    b: B,
};
const B = struct {
    a: A,
};
comptime {
    _ = @as(A, undefined);
}

// error
//
// error: dependency loop with length 2
// :2:8: note: type 'tmp.A' depends on type 'tmp.B' for field declared here
// :5:8: note: type 'tmp.B' depends on type 'tmp.A' for field declared here
// note: eliminate any one of these dependencies to break the loop
