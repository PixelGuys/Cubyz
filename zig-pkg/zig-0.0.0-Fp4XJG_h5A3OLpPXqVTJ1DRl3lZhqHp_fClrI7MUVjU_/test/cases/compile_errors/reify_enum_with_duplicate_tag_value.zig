export fn entry() void {
    const E = @Enum(u32, .nonexhaustive, &.{ "a", "b" }, &.{ 10, 10 });
    _ = E.a;
}

// error
//
// :2:58: error: enum tag value '10' for field 'b' already taken
// :2:58: note: previous occurrence in field 'a'
