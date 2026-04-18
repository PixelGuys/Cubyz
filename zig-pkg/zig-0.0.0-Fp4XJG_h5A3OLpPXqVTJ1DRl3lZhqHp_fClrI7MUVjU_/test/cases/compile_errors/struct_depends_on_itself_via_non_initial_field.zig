const A = struct {
    a: u8,
    bytes: [@sizeOf(A)]u8,
};

comptime {
    _ = @as(A, undefined);
}

// error
//
// :3:21: error: type 'tmp.A' depends on itself for size query here
