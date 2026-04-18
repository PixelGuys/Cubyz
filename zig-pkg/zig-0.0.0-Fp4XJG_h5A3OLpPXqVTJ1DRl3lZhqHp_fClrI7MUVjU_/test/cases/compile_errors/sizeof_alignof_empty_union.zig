const EnumInferred = enum {};
const EnumExplicit = enum(u8) {};
const EnumNonexhaustive = enum(u8) { _ };

const U0 = union {};
const U1 = union(enum) {};
const U2 = union(enum(u8)) {};
const U3 = union(EnumInferred) {};
const U4 = union(EnumExplicit) {};
const U5 = union(EnumNonexhaustive) {};

export fn size0() void {
    _ = @sizeOf(U0);
}
export fn size1() void {
    _ = @sizeOf(U1);
}
export fn size2() void {
    _ = @sizeOf(U2);
}
export fn size3() void {
    _ = @sizeOf(U3);
}
export fn size4() void {
    _ = @sizeOf(U4);
}
export fn size5() void {
    _ = @sizeOf(U5);
}

export fn align0() void {
    _ = @alignOf(U0);
}
export fn align1() void {
    _ = @alignOf(U1);
}
export fn align2() void {
    _ = @alignOf(U2);
}
export fn align3() void {
    _ = @alignOf(U3);
}
export fn align4() void {
    _ = @alignOf(U4);
}
export fn align5() void {
    _ = @alignOf(U5);
}

// error
//
// :13:17: error: no size available for uninstantiable type 'tmp.U0'
// :5:12: note: union declared here
// :16:17: error: no size available for uninstantiable type 'tmp.U1'
// :6:12: note: union declared here
// :19:17: error: no size available for uninstantiable type 'tmp.U2'
// :7:12: note: union declared here
// :22:17: error: no size available for uninstantiable type 'tmp.U3'
// :8:12: note: union declared here
// :25:17: error: no size available for uninstantiable type 'tmp.U4'
// :9:12: note: union declared here
// :28:17: error: no size available for uninstantiable type 'tmp.U5'
// :10:12: note: union declared here
// :32:18: error: no align available for uninstantiable type 'tmp.U0'
// :5:12: note: union declared here
// :35:18: error: no align available for uninstantiable type 'tmp.U1'
// :6:12: note: union declared here
// :38:18: error: no align available for uninstantiable type 'tmp.U2'
// :7:12: note: union declared here
// :41:18: error: no align available for uninstantiable type 'tmp.U3'
// :8:12: note: union declared here
// :44:18: error: no align available for uninstantiable type 'tmp.U4'
// :9:12: note: union declared here
// :47:18: error: no align available for uninstantiable type 'tmp.U5'
// :10:12: note: union declared here
