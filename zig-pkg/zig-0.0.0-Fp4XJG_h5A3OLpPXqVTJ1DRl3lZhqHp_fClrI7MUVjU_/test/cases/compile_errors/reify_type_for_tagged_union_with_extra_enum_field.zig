const Tag = @Enum(u2, .exhaustive, &.{ "signed", "unsigned", "arst" }, &.{ 0, 1, 2 });
const Tagged = @Union(.auto, Tag, &.{ "signed", "unsigned" }, &.{ i32, u32 }, &@splat(.{}));
export fn entry() void {
    var tagged = Tagged{ .signed = -1 };
    tagged = .{ .unsigned = 1 };
}

// error
//
// :2:16: error: enum field 'arst' missing from union
// :1:36: note: enum field here
