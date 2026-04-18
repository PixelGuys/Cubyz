fn entry0() void {
    var a: u32 = 1 + 2;
    _ = a;
}

fn entry1() void {
    const a: u32 = 1;
    const b: u32 = 2;
    var c = a + b;
    const d = c;
    _ = d;
}

fn entry2() void {
    var a: u32 = 123;
    foo(a);
}

fn foo(_: u32) void {}

fn entry3() void {
    var a: [1]u8 = .{0};
    _ = a[0];
}

fn entry4() void {
    var s: struct { a: u8 } = .{ .a = 0 };
    _ = s.a;
}

// error
//
// :2:9: error: local variable is never mutated
// :2:9: note: consider using 'const'
// :9:9: error: local variable is never mutated
// :9:9: note: consider using 'const'
// :15:9: error: local variable is never mutated
// :15:9: note: consider using 'const'
// :22:9: error: local variable is never mutated
// :22:9: note: consider using 'const'
// :27:9: error: local variable is never mutated
// :27:9: note: consider using 'const'
