const Foo = enum { A, B, C };
export fn entry(foo: Foo) void {
    _ = foo;
}

// error
// target=x86_64-linux
//
// :2:17: error: parameter of type 'tmp.Foo' not allowed in function with calling convention 'x86_64_sysv'
// :1:13: note: integer tag type of enum is inferred
// :1:13: note: consider explicitly specifying the integer tag type
// :1:13: note: enum declared here
