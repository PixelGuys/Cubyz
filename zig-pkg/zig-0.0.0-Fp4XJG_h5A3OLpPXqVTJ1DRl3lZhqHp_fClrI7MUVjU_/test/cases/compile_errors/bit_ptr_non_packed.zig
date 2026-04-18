export fn entry1() void {
    const S = extern struct { x: u32 };
    _ = *align(1:2:8) S;
}

export fn entry2() void {
    const S = struct { x: u32 };
    _ = *align(1:2:@sizeOf(S) * 2) S;
}

export fn entry3() void {
    const E = enum { implicit, backing, type };
    _ = *align(1:2:8) E;
}

// error
//
// :3:23: error: bit-pointer cannot refer to value of type 'tmp.entry1.S'
// :3:23: note: non-packed structs do not have a bit-packed representation
// :2:22: note: struct declared here
// :8:36: error: bit-pointer cannot refer to value of type 'tmp.entry2.S'
// :8:36: note: non-packed structs do not have a bit-packed representation
// :7:15: note: struct declared here
// :13:23: error: bit-pointer cannot refer to value of type 'tmp.entry3.E'
// :12:15: note: integer tag type of enum is inferred
// :12:15: note: consider explicitly specifying the integer tag type
