const S = extern struct {
    a: fn () callconv(.c) void,
};
comptime {
    _ = @sizeOf(S) == 1;
}

// error
//
// :2:8: error: extern structs cannot contain fields of type 'fn () callconv(.c) void'
// :2:8: note: type has no guaranteed in-memory representation
// :2:8: note: use '*const ' to make a function pointer type
