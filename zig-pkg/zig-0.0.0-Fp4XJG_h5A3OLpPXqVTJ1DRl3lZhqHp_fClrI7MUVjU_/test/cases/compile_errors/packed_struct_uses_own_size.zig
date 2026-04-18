const S = packed struct {
    x: @Int(.unsigned, @sizeOf(S)),
};
comptime {
    _ = @as(S, undefined);
}

// error
//
// :2:32: error: type 'tmp.S' depends on itself for size query here
