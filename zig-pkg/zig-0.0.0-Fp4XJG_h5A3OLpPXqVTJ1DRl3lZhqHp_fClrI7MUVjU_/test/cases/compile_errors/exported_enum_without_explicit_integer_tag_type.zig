const E = enum { one, two };
comptime {
    @export(&E, .{ .name = "E" });
}
const e: E = .two;
comptime {
    @export(&e, .{ .name = "e" });
}

// error
//
// :3:5: error: unable to export type 'type'
// :7:5: error: unable to export type 'tmp.E'
// :1:11: note: integer tag type of enum is inferred
// :1:11: note: consider explicitly specifying the integer tag type
// :1:11: note: enum declared here
