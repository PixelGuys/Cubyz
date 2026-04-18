export fn f() u32 {
    return bad();
}

inline fn bad() bool {
    return @call(.always_tail, g, .{});
}

fn g() u32 {
    return 123;
}

// error
//
// :6:12: error: expected type 'bool', found 'u32'
// :5:17: note: function return type declared here
// :2:15: note: called inline here
