export fn entry0() void {
    var a = undefined;
    _ = &a;
}
export fn entry1() void {
    var b = 1;
    _ = &b;
}
export fn entry2() void {
    var c = 1.0;
    _ = &c;
}
export fn entry3() void {
    var d = null;
    _ = &d;
}
export fn entry4(opaque_: *Opaque) void {
    var e = opaque_.*;
    _ = &e;
}
export fn entry5() void {
    var f = i32;
    _ = &f;
}
const Opaque = opaque {};
export fn entry6() void {
    var e: Opaque = undefined;
    _ = &e;
}

// error
//
// :2:9: error: variable of type '@TypeOf(undefined)' must be const or comptime
// :6:9: error: variable of type 'comptime_int' must be const or comptime
// :6:9: note: to modify this variable at runtime, it must be given an explicit fixed-size number type
// :10:9: error: variable of type 'comptime_float' must be const or comptime
// :10:9: note: to modify this variable at runtime, it must be given an explicit fixed-size number type
// :14:9: error: variable of type '@TypeOf(null)' must be const or comptime
// :18:20: error: cannot load opaque type 'tmp.Opaque'
// :25:16: note: opaque declared here
// :22:9: error: variable of type 'type' must be const or comptime
// :22:9: note: types are not available at runtime
// :27:12: error: non-extern variable with opaque type 'tmp.Opaque'
// :25:16: note: opaque declared here
