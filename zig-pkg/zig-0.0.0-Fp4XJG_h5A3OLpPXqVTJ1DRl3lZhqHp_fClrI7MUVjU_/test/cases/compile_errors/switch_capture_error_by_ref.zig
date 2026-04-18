export fn entry1() void {
    switch (@as(anyerror, error.MyError)) {
        error.MyError, error.MyOtherError => |*err| _ = err,
        else => {},
    }
}

export fn entry2() void {
    switch (@as(anyerror, error.MyError)) {
        inline error.MyError, error.MyOtherError => |*err| _ = err,
        else => {},
    }
}

export fn entry3() void {
    switch (@as(anyerror, error.MyError)) {
        else => |*err| _ = err,
    }
}

// error
//
// :3:47: error: error set cannot be captured by reference
// :10:54: error: error set cannot be captured by reference
// :17:18: error: error set cannot be captured by reference
