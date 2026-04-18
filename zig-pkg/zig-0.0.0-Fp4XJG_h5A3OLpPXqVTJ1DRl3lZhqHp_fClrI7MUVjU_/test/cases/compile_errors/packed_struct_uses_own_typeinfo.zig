const S = packed struct(u16) {
    a: bool,
    b: bool,
    _padding: @Int(.unsigned, 17 - @typeInfo(S).Struct.fields.len) = 0,
};

comptime {
    _ = @as(S, .{ .a = true, .b = true });
}

// error
//
// :4:36: error: type 'tmp.S' depends on itself for type information query here
