const S = struct { a: u32 };
export fn entry0() void {
    _ = @sizeOf(packed union {
        foo: S,
        bar: bool,
    });
}
export fn entry1() void {
    _ = @sizeOf(packed union {
        x: *const u32,
    });
}

// error
//
// :4:14: error: packed unions cannot contain fields of type 'tmp.S'
// :4:14: note: non-packed structs do not have a bit-packed representation
// :1:11: note: struct declared here
// :10:12: error: packed unions cannot contain fields of type '*const u32'
// :10:12: note: pointers cannot be directly bitpacked
// :10:12: note: consider using 'usize' and '@intFromPtr'
