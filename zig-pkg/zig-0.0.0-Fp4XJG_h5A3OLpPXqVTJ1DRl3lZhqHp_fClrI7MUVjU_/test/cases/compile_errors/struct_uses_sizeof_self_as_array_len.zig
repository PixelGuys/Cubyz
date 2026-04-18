const S = struct {
    a: *[@sizeOf(S)]u8,
};
comptime {
    _ = @as(S, undefined);
}

// error
//
// :2:18: error: type 'tmp.S' depends on itself for size query here
