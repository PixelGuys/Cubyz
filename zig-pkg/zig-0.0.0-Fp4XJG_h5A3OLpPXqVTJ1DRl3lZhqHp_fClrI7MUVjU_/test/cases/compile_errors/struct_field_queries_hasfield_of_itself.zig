const Foo = packed struct {
    bar: (T: {
        _ = @hasField(Foo, "bar");
        break :T void;
    }),
};

comptime {
    _ = @as(Foo, undefined);
}

// error
//
// :3:23: error: type 'tmp.Foo' depends on itself for field query here
