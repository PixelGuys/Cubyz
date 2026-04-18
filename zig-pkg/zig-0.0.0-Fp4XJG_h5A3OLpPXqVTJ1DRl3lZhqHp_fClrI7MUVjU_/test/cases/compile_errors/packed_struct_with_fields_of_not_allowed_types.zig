export fn entry1() void {
    _ = @sizeOf(packed struct {
        x: anyerror,
    });
}
export fn entry2() void {
    _ = @sizeOf(packed struct {
        x: [2]u24,
    });
}
export fn entry3() void {
    _ = @sizeOf(packed struct {
        x: anyerror!u32,
    });
}
export fn entry4() void {
    _ = @sizeOf(packed struct {
        x: S,
    });
}
export fn entry5() void {
    _ = @sizeOf(packed struct {
        x: U,
    });
}
export fn entry6() void {
    _ = @sizeOf(packed struct {
        x: ?anyerror,
    });
}
export fn entry7() void {
    _ = @sizeOf(packed struct {
        x: enum(u1) { A, B },
    });
}
export fn entry8() void {
    _ = @sizeOf(packed struct {
        x: fn () void,
    });
}
export fn entry9() void {
    _ = @sizeOf(packed struct {
        x: *const fn () void,
    });
}
export fn entry10() void {
    _ = @sizeOf(packed struct {
        x: packed struct { x: i32 },
    });
}
export fn entry11() void {
    _ = @sizeOf(packed struct {
        x: packed union { A: i32, B: u32 },
    });
}
const S = struct {
    x: i32,
};
const U = extern union {
    A: i32,
    B: u32,
};
export fn entry12() void {
    _ = @sizeOf(packed struct {
        x: packed struct { a: []u8 },
    });
}
export fn entry13() void {
    _ = @sizeOf(packed struct {
        x: *type,
    });
}
export fn entry14() void {
    const E = enum { implicit, backing, type };
    _ = @sizeOf(packed struct {
        x: E,
    });
}
export fn entry15() void {
    _ = @sizeOf(packed struct {
        x: *const u32,
    });
}

// error
//
// :3:12: error: packed structs cannot contain fields of type 'anyerror'
// :3:12: note: type does not have a bit-packed representation
// :8:12: error: packed structs cannot contain fields of type '[2]u24'
// :8:12: note: type does not have a bit-packed representation
// :13:20: error: packed structs cannot contain fields of type 'anyerror!u32'
// :13:20: note: type does not have a bit-packed representation
// :18:12: error: packed structs cannot contain fields of type 'tmp.S'
// :18:12: note: non-packed structs do not have a bit-packed representation
// :56:11: note: struct declared here
// :23:12: error: packed structs cannot contain fields of type 'tmp.U'
// :23:12: note: non-packed unions do not have a bit-packed representation
// :59:18: note: union declared here
// :28:12: error: packed structs cannot contain fields of type '?anyerror'
// :28:12: note: type does not have a bit-packed representation
// :38:12: error: packed structs cannot contain fields of type 'fn () void'
// :38:12: note: type does not have a bit-packed representation
// :43:12: error: packed structs cannot contain fields of type '*const fn () void'
// :43:12: note: pointers cannot be directly bitpacked
// :43:12: note: consider using 'usize' and '@intFromPtr'
// :65:31: error: packed structs cannot contain fields of type '[]u8'
// :65:31: note: slices do not have a bit-packed representation
// :70:12: error: packed structs cannot contain fields of type '*type'
// :70:12: note: pointers cannot be directly bitpacked
// :70:12: note: consider using 'usize' and '@intFromPtr'
// :76:12: error: packed structs cannot contain fields of type 'tmp.entry14.E'
// :74:15: note: integer tag type of enum is inferred
// :74:15: note: consider explicitly specifying the integer tag type
// :81:12: error: packed structs cannot contain fields of type '*const u32'
// :81:12: note: pointers cannot be directly bitpacked
// :81:12: note: consider using 'usize' and '@intFromPtr'
