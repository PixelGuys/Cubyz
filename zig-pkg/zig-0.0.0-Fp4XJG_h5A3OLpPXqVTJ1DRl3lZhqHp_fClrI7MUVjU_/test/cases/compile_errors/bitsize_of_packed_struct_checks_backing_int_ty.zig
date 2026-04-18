const Foo = packed struct(u32) {
    x: u1,
};
fn bar(_: Foo) callconv(.c) void {}
pub export fn entry() void {
    bar(.{ .x = 0 });
}

// error
//
// :1:20: error: backing integer bit width does not match total bit width of fields
// :1:27: note: backing integer 'u32' has bit width '32'
// :1:20: note: struct fields have total bit width '1'
