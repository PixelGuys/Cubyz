const E = enum(comptime_int) { a };
comptime {
    _ = E.a;
}

// error
//
// :1:16: error: expected integer tag type, found 'comptime_int'
