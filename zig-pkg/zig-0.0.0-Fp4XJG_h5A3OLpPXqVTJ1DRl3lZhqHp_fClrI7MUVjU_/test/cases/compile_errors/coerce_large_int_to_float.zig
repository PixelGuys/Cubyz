// Test that integer types above a certain size will not coerce to a float.

fn testCoerce(Float: type, Int: type) void {
    var i: Int = 0;
    _ = &i;
    _ = @as(Float, i);
}

export fn entry() void {
    testCoerce(f16, u11); // Okay
    testCoerce(f16, u12); // Too big

    testCoerce(f16, i12);
    testCoerce(f16, i13);

    testCoerce(f32, u24);
    testCoerce(f32, u25);

    testCoerce(f32, i25);
    testCoerce(f32, i26);

    testCoerce(f64, u53);
    testCoerce(f64, u54);

    testCoerce(f64, i54);
    testCoerce(f64, i55);

    testCoerce(f80, u64);
    testCoerce(f80, u65);

    testCoerce(f80, i65);
    testCoerce(f80, i66);

    testCoerce(f128, u113);
    testCoerce(f128, u114);

    testCoerce(f128, i114);
    testCoerce(f128, i115);
}

// error
//
// :6:20: error: expected type 'f128', found 'i115'
// :6:20: error: expected type 'f128', found 'u114'
// :6:20: error: expected type 'f16', found 'i13'
// :6:20: error: expected type 'f16', found 'u12'
// :6:20: error: expected type 'f32', found 'i26'
// :6:20: error: expected type 'f32', found 'u25'
// :6:20: error: expected type 'f64', found 'i55'
// :6:20: error: expected type 'f64', found 'u54'
// :6:20: error: expected type 'f80', found 'i66'
// :6:20: error: expected type 'f80', found 'u65'
