export fn foo() void {
    const U = extern union {};
    _ = @as(U, undefined);
}

// error
//
// :2:22: error: extern union has no fields
