const EnumInferred = enum {};
const EnumExplicit = enum(u8) {};
const EnumNonexhaustive = enum(u8) { _ };

const U0 = union {};
const U1 = union(enum) {};
const U2 = union(enum(u8)) {};
const U3 = union(EnumInferred) {};
const U4 = union(EnumExplicit) {};
const U5 = union(EnumNonexhaustive) {};

export fn init0() void {
    _ = @as(U0, undefined);
}
export fn init1() void {
    _ = @as(U1, undefined);
}
export fn init2() void {
    _ = @as(U2, undefined);
}
export fn init3() void {
    _ = @as(U3, undefined);
}
export fn init4() void {
    _ = @as(U4, undefined);
}
export fn init5() void {
    _ = @as(U5, undefined);
}

export fn deref0(ptr: *const U0) void {
    _ = ptr.*;
}
export fn deref1(ptr: *const U1) void {
    _ = ptr.*;
}
export fn deref2(ptr: *const U2) void {
    _ = ptr.*;
}
export fn deref3(ptr: *const U3) void {
    _ = ptr.*;
}
export fn deref4(ptr: *const U4) void {
    _ = ptr.*;
}
export fn deref5(ptr: *const U5) void {
    _ = ptr.*;
}

// error
//
// :13:17: error: expected type 'tmp.U0', found '@TypeOf(undefined)'
// :13:17: note: cannot coerce to uninstantiable type 'tmp.U0'
// :5:12: note: union declared here
// :16:17: error: expected type 'tmp.U1', found '@TypeOf(undefined)'
// :16:17: note: cannot coerce to uninstantiable type 'tmp.U1'
// :6:12: note: union declared here
// :19:17: error: expected type 'tmp.U2', found '@TypeOf(undefined)'
// :19:17: note: cannot coerce to uninstantiable type 'tmp.U2'
// :7:12: note: union declared here
// :22:17: error: expected type 'tmp.U3', found '@TypeOf(undefined)'
// :22:17: note: cannot coerce to uninstantiable type 'tmp.U3'
// :8:12: note: union declared here
// :25:17: error: expected type 'tmp.U4', found '@TypeOf(undefined)'
// :25:17: note: cannot coerce to uninstantiable type 'tmp.U4'
// :9:12: note: union declared here
// :28:17: error: expected type 'tmp.U5', found '@TypeOf(undefined)'
// :28:17: note: cannot coerce to uninstantiable type 'tmp.U5'
// :10:12: note: union declared here
// :32:12: error: cannot load uninstantiable type 'tmp.U0'
// :5:12: note: union declared here
// :35:12: error: cannot load uninstantiable type 'tmp.U1'
// :6:12: note: union declared here
// :38:12: error: cannot load uninstantiable type 'tmp.U2'
// :7:12: note: union declared here
// :41:12: error: cannot load uninstantiable type 'tmp.U3'
// :8:12: note: union declared here
// :44:12: error: cannot load uninstantiable type 'tmp.U4'
// :9:12: note: union declared here
// :47:12: error: cannot load uninstantiable type 'tmp.U5'
// :10:12: note: union declared here
