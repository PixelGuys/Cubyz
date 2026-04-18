export fn entry() void {
    const E = @Enum(u32, .nonexhaustive, &.{ "A", "A" }, &.{ 0, 1 });
    _ = @as(E, undefined);
}

// error
//
// :2:42: error: duplicate enum field 'A' at index '1'
// :2:42: note: previous field at index '0'
