var rt: usize = 0;
export fn foo() void {
    const x: [*]const type = &.{ u8, u16 };
    _ = x[rt];
}

// error
//
// :4:11: error: values of type 'type' must be comptime-known, but index value is runtime-known
// :4:10: note: types are not available at runtime
