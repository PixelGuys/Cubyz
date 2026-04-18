const S = struct {
    const Foo = struct {
        y: Bar,
    };
    const Bar = struct {
        y: if (@sizeOf(Foo) == 0) u64 else void,
    };
};
comptime {
    _ = @sizeOf(S.Foo) + 1;
}

// error
//
// error: dependency loop with length 2
// :3:12: note: type 'tmp.S.Foo' depends on type 'tmp.S.Bar' for field declared here
// :6:24: note: type 'tmp.S.Bar' depends on type 'tmp.S.Foo' for size query here
// note: eliminate any one of these dependencies to break the loop
