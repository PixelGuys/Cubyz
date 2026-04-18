export fn foo() void {
    const U = packed union {};
    _ = @as(U, undefined);
}

// error
//
// :2:22: error: packed union has no fields
