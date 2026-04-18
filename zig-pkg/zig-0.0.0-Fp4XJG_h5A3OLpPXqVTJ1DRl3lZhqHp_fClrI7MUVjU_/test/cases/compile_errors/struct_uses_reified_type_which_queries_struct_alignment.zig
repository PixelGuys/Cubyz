const A = struct { b: *B };
const B = @Struct(.auto, null, &.{"x"}, &.{A}, &.{.{ .@"align" = @alignOf(A) }});
comptime {
    _ = @as(A, undefined);
    _ = @as(B, undefined);
}

// error
//
// error: dependency loop with length 2
// :1:24: note: type 'tmp.A' uses value of declaration 'tmp.B' here
// :2:75: note: value of declaration 'tmp.B' depends on type 'tmp.A' for alignment query here
// note: eliminate any one of these dependencies to break the loop
