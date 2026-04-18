// Test that peer type resolution fails for integer types that cannot safely coerce to a float.

fn testAdd(Float: type, Int: type) void {
    var i: Int = 0;
    _ = &i;
    var f: Float = 0;
    _ = &f;
    _ = i + f;
    _ = f + i;
}

export fn entry() void {
    testAdd(f16, u11); // Okay
    testAdd(f16, u12); // Too big

    testAdd(f16, i12);
    testAdd(f16, i13);

    testAdd(f32, u24);
    testAdd(f32, u25);

    testAdd(f32, i25);
    testAdd(f32, i26);

    testAdd(f64, u53);
    testAdd(f64, u54);

    testAdd(f64, i54);
    testAdd(f64, i55);

    testAdd(f80, u64);
    testAdd(f80, u65);

    testAdd(f80, i65);
    testAdd(f80, i66);

    testAdd(f128, u113);
    testAdd(f128, u114);

    testAdd(f128, i114);
    testAdd(f128, i115);
}

// error
//
// :8:11: error: incompatible types: 'i115' and 'f128'
// :8:9: note: type 'i115' here
// :8:13: note: type 'f128' here
// :8:11: error: incompatible types: 'i13' and 'f16'
// :8:9: note: type 'i13' here
// :8:13: note: type 'f16' here
// :8:11: error: incompatible types: 'i26' and 'f32'
// :8:9: note: type 'i26' here
// :8:13: note: type 'f32' here
// :8:11: error: incompatible types: 'i55' and 'f64'
// :8:9: note: type 'i55' here
// :8:13: note: type 'f64' here
// :8:11: error: incompatible types: 'i66' and 'f80'
// :8:9: note: type 'i66' here
// :8:13: note: type 'f80' here
// :8:11: error: incompatible types: 'u114' and 'f128'
// :8:9: note: type 'u114' here
// :8:13: note: type 'f128' here
// :8:11: error: incompatible types: 'u12' and 'f16'
// :8:9: note: type 'u12' here
// :8:13: note: type 'f16' here
// :8:11: error: incompatible types: 'u25' and 'f32'
// :8:9: note: type 'u25' here
// :8:13: note: type 'f32' here
// :8:11: error: incompatible types: 'u54' and 'f64'
// :8:9: note: type 'u54' here
// :8:13: note: type 'f64' here
// :8:11: error: incompatible types: 'u65' and 'f80'
// :8:9: note: type 'u65' here
// :8:13: note: type 'f80' here
