const Tag = @Enum(u1, .exhaustive, &.{ "signed", "unsigned" }, &.{ 0, 1 });
const Tagged = @Union(.auto, Tag, &.{}, &.{}, &.{});
export fn entry() void {
    const tagged: Tagged = undefined;
    _ = tagged;
}

// error
//
// :2:16: error: enum field 'signed' missing from union
// :1:36: note: enum field here
