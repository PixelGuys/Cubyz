const Error = error{M};

export fn entry1() void {
    var f: Error!void = {};
    _ = &f;
    if (f) {} else |e| switch (e) {}
}

export fn entry2() void {
    var f: Error!void = {};
    _ = &f;
    f catch |e| switch (e) {};
}

export fn entry3() void {
    const f: Error!void = error.M;
    if (f) {} else |e| switch (e) {}
}

export fn entry4() void {
    const f: Error!void = error.M;
    f catch |e| switch (e) {};
}

// error
//
// :6:24: error: switch must handle all possibilities
// :6:24: note: unhandled error value: 'error.M'
// :12:17: error: switch must handle all possibilities
// :12:17: note: unhandled error value: 'error.M'
// :17:24: error: switch must handle all possibilities
// :17:24: note: unhandled error value: 'error.M'
// :22:17: error: switch must handle all possibilities
// :22:17: note: unhandled error value: 'error.M'
