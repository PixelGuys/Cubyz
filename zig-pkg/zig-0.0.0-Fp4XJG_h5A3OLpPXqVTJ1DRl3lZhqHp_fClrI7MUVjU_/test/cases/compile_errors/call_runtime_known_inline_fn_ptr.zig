export fn entry() void {
    var a = &b;
    a = a;
    a();
}
inline fn b() void {}

// error
//
// :4:5: error: unable to resolve comptime value
// :4:5: note: function being called inline must be comptime-known
