const E = enum(u9) {
    const a_val: @typeInfo(E).@"enum".tag_type = 0;
    a = a_val,
};
comptime {
    _ = E.a;
}

// error
//
// error: dependency loop with length 3
// :3:9: note: type 'tmp.E' uses value of declaration 'tmp.E.a_val' here
// :2:50: note: value of declaration 'tmp.E.a_val' uses type of declaration 'tmp.E.a_val' here
// :2:18: note: type of declaration 'tmp.E.a_val' depends on type 'tmp.E' for type information query here
// note: eliminate any one of these dependencies to break the loop
