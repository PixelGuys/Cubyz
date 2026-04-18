const S = extern struct {
    f: struct { u32 },
};

comptime {
    _ = @sizeOf(S);
}

// error
//
// :2:8: error: extern structs cannot contain fields of type 'struct { u32 }'
// :2:8: note: tuples have no guaranteed in-memory representation
