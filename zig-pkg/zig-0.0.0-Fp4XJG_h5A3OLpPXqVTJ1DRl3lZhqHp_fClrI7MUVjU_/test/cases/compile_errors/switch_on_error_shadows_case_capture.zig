export fn entry1() void {
    const e: error{Foo}!u32 = error.Foo;
    e catch |err| switch (err) {
        error.Foo => |err| {
            _ = err catch {};
        },
    };
}

export fn entry2() void {
    const e: error{Foo}!u32 = error.Foo;
    if (e) {} else |err| switch (err) {
        error.Foo => |err| {
            _ = err catch {};
        },
    }
}

// error
//
// :4:23: error: redeclaration of capture 'err'
// :3:14: note: previous declaration here
// :13:23: error: redeclaration of capture 'err'
// :12:21: note: previous declaration here
