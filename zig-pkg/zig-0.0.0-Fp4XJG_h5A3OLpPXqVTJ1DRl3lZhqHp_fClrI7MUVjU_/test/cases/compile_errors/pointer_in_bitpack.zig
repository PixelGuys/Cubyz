const S = packed struct {
    ptr: *u32,
};
export fn foo() void {
    _ = @as(S, undefined);
}

const U = packed union {
    ptr: *u32,
};
export fn bar() void {
    _ = @as(U, undefined);
}

// error
//
// :2:10: error: packed structs cannot contain fields of type '*u32'
// :2:10: note: pointers cannot be directly bitpacked
// :2:10: note: consider using 'usize' and '@intFromPtr'
// :9:10: error: packed unions cannot contain fields of type '*u32'
// :9:10: note: pointers cannot be directly bitpacked
// :9:10: note: consider using 'usize' and '@intFromPtr'
