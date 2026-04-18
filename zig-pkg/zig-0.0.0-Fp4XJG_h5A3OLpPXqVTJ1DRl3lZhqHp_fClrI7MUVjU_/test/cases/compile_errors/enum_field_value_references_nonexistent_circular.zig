pub const Foo = enum(c_int) {
    A = Foo.B,
    C = D,
};
export fn entry() void {
    const s: Foo = Foo.E;
    _ = s;
}
const D = 1;

// error
//
// :2:12: error: type 'tmp.Foo' depends on itself for field usage here
