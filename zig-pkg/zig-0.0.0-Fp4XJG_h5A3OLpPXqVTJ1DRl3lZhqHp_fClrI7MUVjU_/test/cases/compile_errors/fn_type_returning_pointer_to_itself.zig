const MyFn = fn () ?*const MyFn;
comptime {
    _ = MyFn;
}

// error
//
// :1:28: error: value of declaration 'tmp.MyFn' depends on itself here
