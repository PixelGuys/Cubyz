const A = struct {
    a: A,
};
export fn entry() usize {
    return @sizeOf(A);
}

// error
//
// :2:8: error: type 'tmp.A' depends on itself for field declared here
