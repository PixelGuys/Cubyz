const Foo = union {
    x: Foo,
};

var foo: Foo = undefined;

export fn entry() usize {
    return @sizeOf(@TypeOf(foo.x));
}

// error
//
// :2:8: error: type 'tmp.Foo' depends on itself for field declared here
