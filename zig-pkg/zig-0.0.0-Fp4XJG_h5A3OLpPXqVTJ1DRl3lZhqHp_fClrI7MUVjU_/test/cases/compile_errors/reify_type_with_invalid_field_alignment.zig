comptime {
    _ = @Union(.auto, null, &.{"foo"}, &.{usize}, &.{.{ .@"align" = 3 }});
}
comptime {
    _ = @Struct(.auto, null, &.{"a"}, &.{u32}, &.{.{
        .@"comptime" = true,
        .@"align" = 5,
        .default_value_ptr = &@as(u32, 0),
    }});
}
comptime {
    _ = @Pointer(.many, .{ .@"align" = 7 }, u8, null);
}

// error
//
// :2:51: error: alignment value '3' is not a power of two
// :5:48: error: alignment value '5' is not a power of two
// :12:26: error: alignment value '7' is not a power of two
