export fn entry0() usize {
    return @sizeOf(@TypeOf(null));
}
export fn entry1() usize {
    return @sizeOf(comptime_int);
}
export fn entry2() usize {
    return @sizeOf(noreturn);
}
const S3 = struct { a: u32, b: comptime_int };
export fn entry3() usize {
    return @sizeOf(S3);
}
const S4 = struct { a: u32, b: noreturn };
export fn entry4() usize {
    return @sizeOf(S4);
}
export fn entry5() usize {
    return @sizeOf([1]fn () void);
}

// error
//
// :2:20: error: no size available for comptime-only type '@TypeOf(null)'
// :5:20: error: no size available for comptime-only type 'comptime_int'
// :8:20: error: no size available for uninstantiable type 'noreturn'
// :12:20: error: no size available for comptime-only type 'tmp.S3'
// :10:12: note: struct declared here
// :16:20: error: no size available for uninstantiable type 'tmp.S4'
// :14:12: note: struct declared here
// :19:20: error: no size available for comptime-only type '[1]fn () void'
