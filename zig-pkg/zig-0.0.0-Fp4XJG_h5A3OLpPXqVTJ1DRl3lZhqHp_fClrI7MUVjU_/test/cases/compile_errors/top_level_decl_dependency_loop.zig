const a: @TypeOf(b) = 0;
const b: @TypeOf(a) = 0;
export fn entry() void {
    const c = a + b;
    _ = c;
}

// error
//
// error: dependency loop with length 4
// :1:23: note: value of declaration 'tmp.a' uses type of declaration 'tmp.a' here
// :1:18: note: type of declaration 'tmp.a' uses value of declaration 'tmp.b' here
// :2:23: note: value of declaration 'tmp.b' uses type of declaration 'tmp.b' here
// :2:18: note: type of declaration 'tmp.b' uses value of declaration 'tmp.a' here
// note: eliminate any one of these dependencies to break the loop
