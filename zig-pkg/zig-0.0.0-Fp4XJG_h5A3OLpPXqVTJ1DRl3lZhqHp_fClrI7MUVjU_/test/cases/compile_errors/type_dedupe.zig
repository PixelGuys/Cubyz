const SomeVeryVeryVeryLongName = struct {};

fn foo(a: *SomeVeryVeryVeryLongName) void {
    _ = a;
}

export fn entry() void {
    const a: SomeVeryVeryVeryLongName = .{};

    foo(a);
}

// error
//
// :10:9: error: expected type '*T', found 'T'
// :10:9: note: T = tmp.SomeVeryVeryVeryLongName
// :1:34: note: struct declared here
// :3:11: note: parameter type declared here
