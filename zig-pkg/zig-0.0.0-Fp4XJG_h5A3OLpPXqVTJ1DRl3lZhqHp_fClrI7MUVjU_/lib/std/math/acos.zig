// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/math/acosf.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/acos.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/acosl.c
//
// Ported from ARM-software, which is licensed under the MIT license:
// https://github.com/ARM-software/optimized-routines/blob/master/LICENSE
//
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/acosf.c
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/acos.c

const std = @import("../std.zig");
const math = std.math;
const testing = std.testing;
const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

/// Returns the arc-cosine of x.
///
/// Special cases:
///  - acos(x)   = nan if x < -1 or x > 1
pub fn acos(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .float => |info| switch (info.bits) {
            16 => return acosBinary16(x),
            32 => return acosBinary32(x),
            64 => return acosBinary64(x),
            80 => return acosExtended80(x),
            128 => return acosBinary128(x),
            else => comptime unreachable,
        },
        .vector => |info| switch (info.child) {
            f32 => return acosBinary32Vec(info.len, x),
            f64 => return acosBinary64Vec(info.len, x),
            else => @compileError("unimplemented"),
        },
        else => comptime unreachable,
    }
}

fn approxBinary16(z: f32) f32 {
    const S0: f32 = 1.0000001e0;
    const S1: f32 = 1.6664918e-1;
    const S2: f32 = 7.55022e-2;
    const S3: f32 = 3.9513987e-2;
    const S4: f32 = 5.0883885e-2;
    return S0 + z * (S1 + z * (S2 + z * (S3 + z * S4)));
}

fn acosBinary16(x: f16) f16 {
    const pio2: f32 = math.pi / 2.0;

    const hx: u16 = @bitCast(x);
    const ix: u16 = hx & 0x7fff;

    // |x| >= 1 or nan
    if (ix >= 0x3c00) {
        if (ix == 0x3c00) {
            if (hx >> 15 != 0) {
                return @floatCast(2.0 * pio2 + 0x1p-120);
            }
            return 0.0;
        }
        return 0.0 / (x - x);
    }

    const xf: f32 = @floatCast(x);

    // |x| < 0.5
    if (ix < 0x3800) {
        return @floatCast(pio2 - xf * approxBinary16(xf * xf));
    }

    // x < -0.5
    if (hx >> 15 != 0) {
        const z = (1.0 + xf) * 0.5;
        const s = @sqrt(z);
        const w = approxBinary16(z) * s;
        return @floatCast(2.0 * (pio2 - w));
    }

    // x > 0.5
    const z = (1.0 - xf) * 0.5;
    const s = @sqrt(z);
    const w = approxBinary16(z) * s;
    return @floatCast(2.0 * w);
}

fn rationalApproxBinary32(z: f32) f32 {
    const pS0: f32 = 1.6666586697e-01;
    const pS1: f32 = -4.2743422091e-02;
    const pS2: f32 = -8.6563630030e-03;
    const qS1: f32 = -7.0662963390e-01;

    // f64 is used instead of f32 to avoid
    // a vectorization on x86_64. The vectorization
    // causes extra floating point execeptions
    // that are prohibited by libc-test.
    const p: f64 = @as(f64, @floatCast(z)) * (pS0 + z * (pS1 + z * pS2));
    const q: f64 = 1.0 + z * qS1;
    return @floatCast(p / q);
}

fn acosBinary32(x: f32) f32 {
    const pio2_hi: f32 = 1.5707962513e+00;
    const pio2_lo: f32 = 7.5497894159e-08;

    const hx: u32 = @bitCast(x);
    const ix: u32 = hx & 0x7fff_ffff;

    // |x| >= 1 or nan
    if (ix >= 0x3f800000) {
        if (ix == 0x3f800000) {
            if (hx >> 31 != 0) {
                return 2.0 * pio2_hi + 0x1.0p-120;
            }
            return 0.0;
        }
        return 0.0 / (x - x);
    }

    // |x| < 0.5
    if (ix < 0x3f00_0000) {
        // |x| < 2^(-26)
        if (ix <= 0x3280_0000) {
            return pio2_hi + 0x1.0p-120;
        }
        return pio2_hi - (x - (pio2_lo - x * rationalApproxBinary32(x * x)));
    }

    // x < -0.5
    if (hx >> 31 != 0) {
        const z = (1 + x) * 0.5;
        const s = @sqrt(z);
        const w = rationalApproxBinary32(z) * s - pio2_lo;
        return 2.0 * (pio2_hi - (s + w));
    }

    // x > 0.5
    const z = (1.0 - x) * 0.5;
    const s = @sqrt(z);
    const hs: u32 = @bitCast(s);
    const df: f32 = @bitCast(hs & 0xffff_f000);
    const c = (z - df * df) / (s + df);
    const w = rationalApproxBinary32(z) * s + c;
    return 2.0 * (df + w);
}

fn rationalApproxBinary64(z: f64) f64 {
    const pS0: f64 = 1.66666666666666657415e-01;
    const pS1: f64 = -3.25565818622400915405e-01;
    const pS2: f64 = 2.01212532134862925881e-01;
    const pS3: f64 = -4.00555345006794114027e-02;
    const pS4: f64 = 7.91534994289814532176e-04;
    const pS5: f64 = 3.47933107596021167570e-05;
    const qS1: f64 = -2.40339491173441421878e+00;
    const qS2: f64 = 2.02094576023350569471e+00;
    const qS3: f64 = -6.88283971605453293030e-01;
    const qS4: f64 = 7.70381505559019352791e-02;

    const p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))));
    const q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)));
    return p / q;
}

fn acosBinary64(x: f64) f64 {
    const pio2_hi: f64 = 1.57079632679489655800e+00;
    const pio2_lo: f64 = 6.12323399573676603587e-17;

    const hx: u32 = @intCast(@as(u64, @bitCast(x)) >> 32);
    const ix: u32 = hx & 0x7fff_ffff;

    // |x| >= 1 or nan
    if (ix >= 0x3ff0_0000) {
        const lx: u32 = @truncate(@as(u64, @bitCast(x)));
        if ((ix - 0x3ff0_0000 | lx) == 0) {
            if (hx >> 31 != 0) {
                return 2.0 * pio2_hi + 0x1.0p-120;
            }
            return 0.0;
        }
        return 0.0 / (x - x);
    }

    // |x| < 0.5
    if (ix < 0x3fe0_0000) {
        // |x| < 2^(-57)
        if (ix <= 0x3c60_0000) {
            return pio2_hi + 0x1.0p-120;
        }
        return pio2_hi - (x - (pio2_lo - x * rationalApproxBinary64(x * x)));
    }

    // x < -0.5
    if (hx >> 31 != 0) {
        const z = (1.0 + x) * 0.5;
        const s = @sqrt(z);
        const w = rationalApproxBinary64(z) * s - pio2_lo;
        return 2 * (pio2_hi - (s + w));
    }

    // x > 0.5
    const z = (1.0 - x) * 0.5;
    const s = @sqrt(z);
    const df: f64 = @bitCast(@as(u64, @bitCast(s)) & 0xffff_ffff_0000_0000);
    const c = (z - df * df) / (s + df);
    const w = rationalApproxBinary64(z) * s + c;
    return 2.0 * (df + w);
}

fn rationalApproxExtended80(z: f80) f80 {
    const pS0: f80 = 1.66666666666666666631e-01;
    const pS1: f80 = -4.16313987993683104320e-01;
    const pS2: f80 = 3.69068046323246813704e-01;
    const pS3: f80 = -1.36213932016738603108e-01;
    const pS4: f80 = 1.78324189708471965733e-02;
    const pS5: f80 = -2.19216428382605211588e-04;
    const pS6: f80 = -7.10526623669075243183e-06;
    const qS1: f80 = -2.94788392796209867269e+00;
    const qS2: f80 = 3.27309890266528636716e+00;
    const qS3: f80 = -1.68285799854822427013e+00;
    const qS4: f80 = 3.90699412641738801874e-01;
    const qS5: f80 = -3.14365703596053263322e-02;

    const p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * (pS5 + z * pS6))))));
    const q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * (qS4 + z * qS5))));
    return p / q;
}

fn acosExtended80(x: f80) f80 {
    const pio2_hi: f80 = 1.57079632679489661926;
    const pio2_lo: f80 = -2.50827880633416601173e-20;

    const hx: u80 = @bitCast(x);
    const se: u16 = @truncate(hx >> 64);
    const e = se & 0x7fff;

    // |x| >= 1 or nan
    if (e >= 0x3fff) {
        if (x == 1.0) {
            return 0.0;
        }
        if (x == -1.0) {
            return 2.0 * pio2_hi + 0x1p-120;
        }
        return 0.0 / (x - x);
    }
    // |x| < 0.5
    if (e < 0x3fff - 1) {
        if (e < 0x3fff - math.floatFractionalBits(f80)) {
            return pio2_hi + 0x1p-120;
        }
        return pio2_hi - (rationalApproxExtended80(x * x) * x - pio2_lo + x);
    }
    // x < -0.5
    if (se >> 15 != 0) {
        const z = (1 + x) * 0.5;
        const s = @sqrt(z);
        return 2.0 * (pio2_hi - (rationalApproxExtended80(z) * s - pio2_lo + s));
    }
    // x > 0.5
    const z = (1.0 - x) * 0.5;
    const s = @sqrt(z);
    const hs: u80 = @bitCast(s);
    const f: f80 = @bitCast(hs & 0xffff_ffff_ffff_0000_0000);
    const c = (z - f * f) / (s + f);
    return 2.0 * (rationalApproxExtended80(z) * s + c + f);
}

fn rationalApproxBinary128(z: f128) f128 {
    const pS0: f128 = 1.66666666666666666666666666666700314e-01;
    const pS1: f128 = -7.32816946414566252574527475428622708e-01;
    const pS2: f128 = 1.34215708714992334609030036562143589e+00;
    const pS3: f128 = -1.32483151677116409805070261790752040e+00;
    const pS4: f128 = 7.61206183613632558824485341162121989e-01;
    const pS5: f128 = -2.56165783329023486777386833928147375e-01;
    const pS6: f128 = 4.80718586374448793411019434585413855e-02;
    const pS7: f128 = -4.42523267167024279410230886239774718e-03;
    const pS8: f128 = 1.44551535183911458253205638280410064e-04;
    const pS9: f128 = -2.10558957916600254061591040482706179e-07;
    const qS1: f128 = -4.84690167848739751544716485245697428e+00;
    const qS2: f128 = 9.96619113536172610135016921140206980e+00;
    const qS3: f128 = -1.13177895428973036660836798461641458e+01;
    const qS4: f128 = 7.74004374389488266169304117714658761e+00;
    const qS5: f128 = -3.25871986053534084709023539900339905e+00;
    const qS6: f128 = 8.27830318881232209752469022352928864e-01;
    const qS7: f128 = -1.18768052702942805423330715206348004e-01;
    const qS8: f128 = 8.32600764660522313269101537926539470e-03;
    const qS9: f128 = -1.99407384882605586705979504567947007e-04;

    const p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * (pS5 + z * (pS6 + z * (pS7 + z * (pS8 + z * pS9)))))))));
    const q = 1.0 + z * (qS1 + z * (qS2 + z * (qS3 + z * (qS4 + z * (qS5 + z * (qS6 + z * (qS7 + z * (qS8 + z * qS9))))))));
    return p / q;
}

fn acosBinary128(x: f128) f128 {
    const pio2_hi: f128 = 1.57079632679489661923132169163975140;
    const pio2_lo: f128 = 4.33590506506189051239852201302167613e-35;

    const hx: u128 = @bitCast(x);
    const se: u16 = @truncate(hx >> 112);
    const e = se & 0x7fff;

    // |x| >= 1 or nan
    if (e >= 0x3fff) {
        if (x == 1.0) {
            return 0.0;
        }
        if (x == -1.0) {
            return 2 * pio2_hi + 0x1p-120;
        }
        return 0.0 / (x - x);
    }
    // |x| < 0.5
    if (e < 0x3fff - 1) {
        if (e < 0x3fff - math.floatFractionalBits(f128)) {
            return pio2_hi + 0x1p-120;
        }
        return pio2_hi - (rationalApproxBinary128(x * x) * x - pio2_lo + x);
    }
    // x < -0.5
    if (se >> 15 != 0) {
        const z = (1 + x) * 0.5;
        const s = @sqrt(z);
        return 2 * (pio2_hi - (rationalApproxBinary128(z) * s - pio2_lo + s));
    }
    // x > 0.5
    const z = (1.0 - x) * 0.5;
    const s = @sqrt(z);
    const hs: u128 = @bitCast(s);
    const f: f128 = @bitCast(hs & 0xffff_ffff_ffff_ffff_0000_0000_0000_0000);
    const c = (z - f * f) / (s + f);
    return 2.0 * (rationalApproxBinary128(z) * s + c + f);
}

test "acosBinary16.special" {
    try testing.expectApproxEqAbs(0x1.92p0, acosBinary16(0x0p+0), math.floatEpsAt(f16, 0x1.92p0));
    try testing.expectApproxEqAbs(0x1.92p1, acosBinary16(-0x1p+0), math.floatEpsAt(f16, 0x1.92p1));
    try testing.expectEqual(0x0p+0, acosBinary16(0x1p+0));
    try testing.expect(math.isNan(acosBinary16(0x1.004p0)));
    try testing.expect(math.isNan(acosBinary16(-0x1.004p0)));
    try testing.expect(math.isNan(acosBinary16(math.inf(f16))));
    try testing.expect(math.isNan(acosBinary16(-math.inf(f16))));
    try testing.expect(math.isNan(acosBinary16(math.nan(f16))));
}

test "acosBinary16" {
    try testing.expectApproxEqAbs(0x1.834p0, acosBinary16(0x1.db4p-5), math.floatEpsAt(f16, 0x1.834p0));
    try testing.expectApproxEqAbs(0x1.d48p0, acosBinary16(-0x1.068p-2), math.floatEpsAt(f16, 0x1.d48p0));
    try testing.expectApproxEqAbs(0x1.b7cp0, acosBinary16(-0x1.2c4p-3), math.floatEpsAt(f16, 0x1.b7cp0));
    try testing.expectApproxEqAbs(0x1.654p0, acosBinary16(0x1.65p-3), math.floatEpsAt(f16, 0x1.654p0));
    try testing.expectApproxEqAbs(0x1.6d8p-2, acosBinary16(0x1.dfcp-1), math.floatEpsAt(f16, 0x1.6d8p-2));
    try testing.expectApproxEqAbs(0x1.32p1, acosBinary16(-0x1.764p-1), math.floatEpsAt(f16, 0x1.32p1));
    try testing.expectApproxEqAbs(0x1.5b8p0, acosBinary16(0x1.b18p-3), math.floatEpsAt(f16, 0x1.5b8p0));
    try testing.expectApproxEqAbs(0x1.668p0, acosBinary16(0x1.5acp-3), math.floatEpsAt(f16, 0x1.668p0));
    try testing.expectApproxEqAbs(0x1.134p1, acosBinary16(-0x1.18cp-1), math.floatEpsAt(f16, 0x1.134p1));
    try testing.expectApproxEqAbs(0x1.0dp1, acosBinary16(-0x1.03p-1), math.floatEpsAt(f16, 0x1.0dp1));
}

test "acosBinary32.special" {
    try testing.expectApproxEqAbs(0x1.921fb6p+0, acosBinary32(0x0p+0), math.floatEpsAt(f32, 0x1.921fb6p+0));
    try testing.expectApproxEqAbs(0x1.921fb6p+1, acosBinary32(-0x1p+0), math.floatEpsAt(f32, 0x1.921fb6p+1));
    try testing.expectEqual(0x0p+0, acosBinary32(0x1p+0));
    try testing.expect(math.isNan(acosBinary32(0x1.000002p+0)));
    try testing.expect(math.isNan(acosBinary32(-0x1.000002p+0)));
    try testing.expect(math.isNan(acosBinary32(math.inf(f32))));
    try testing.expect(math.isNan(acosBinary32(-math.inf(f32))));
    try testing.expect(math.isNan(acosBinary32(math.nan(f32))));
}

test "acosBinary32" {
    try testing.expectApproxEqAbs(0x1.d7c4e6p+0, acosBinary32(-0x1.13284cp-2), math.floatEpsAt(f32, 0x1.d7c4e6p+0));
    try testing.expectApproxEqAbs(0x1.8e6756p-1, acosBinary32(0x1.6ca8ep-1), math.floatEpsAt(f32, 0x1.8e6756p-1));
    try testing.expectApproxEqAbs(0x1.f9d74cp-2, acosBinary32(0x1.c2ca6p-1), math.floatEpsAt(f32, 0x1.f9d74cp-2));
    try testing.expectApproxEqAbs(0x1.26abdcp+1, acosBinary32(-0x1.55f12p-1), math.floatEpsAt(f32, 0x1.26abdcp+1));
    try testing.expectApproxEqAbs(0x1.d85a44p+0, acosBinary32(-0x1.15679ep-2), math.floatEpsAt(f32, 0x1.d85a44p+0));
    try testing.expectApproxEqAbs(0x1.9c2f68p+0, acosBinary32(-0x1.41e132p-5), math.floatEpsAt(f32, 0x1.9c2f68p+0));
    try testing.expectApproxEqAbs(0x1.e881bp-1, acosBinary32(0x1.281b0ep-1), math.floatEpsAt(f32, 0x1.e881bp-1));
    try testing.expectApproxEqAbs(0x1.1713f6p-1, acosBinary32(0x1.b5ce34p-1), math.floatEpsAt(f32, 0x1.1713f6p-1));
    try testing.expectApproxEqAbs(0x1.bd5accp+0, acosBinary32(-0x1.583482p-3), math.floatEpsAt(f32, 0x1.bd5accp+0));
    try testing.expectApproxEqAbs(0x1.6ce7d8p+1, acosBinary32(-0x1.ea8224p-1), math.floatEpsAt(f32, 0x1.6ce7d8p+1));
}

test "acosBinary64.special" {
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+0, acosBinary64(0x0p+0), math.floatEpsAt(f64, 0x1.921fb54442d18p+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+1, acosBinary64(-0x1p+0), math.floatEpsAt(f64, 0x1.921fb54442d18p+1));
    try testing.expectEqual(0x0p+0, acosBinary64(0x1p+0));
    try testing.expect(math.isNan(acosBinary64(0x1.0000000000001p+0)));
    try testing.expect(math.isNan(acosBinary64(-0x1.0000000000001p+0)));
    try testing.expect(math.isNan(acosBinary64(math.inf(f64))));
    try testing.expect(math.isNan(acosBinary64(-math.inf(f64))));
    try testing.expect(math.isNan(acosBinary64(math.nan(f64))));
}

test "acosBinary64" {
    try testing.expectApproxEqAbs(0x1.d7c4e61020905p+0, acosBinary64(-0x1.13284b2b5006dp-2), math.floatEpsAt(f64, 0x1.d7c4e61020905p+0));
    try testing.expectApproxEqAbs(0x1.8e6756e27c366p-1, acosBinary64(0x1.6ca8dfb825911p-1), math.floatEpsAt(f64, 0x1.8e6756e27c366p-1));
    try testing.expectApproxEqAbs(0x1.f9d748eaf956p-2, acosBinary64(0x1.c2ca609de7505p-1), math.floatEpsAt(f64, 0x1.f9d748eaf956p-2));
    try testing.expectApproxEqAbs(0x1.26abdc68d07aap+1, acosBinary64(-0x1.55f11fba96889p-1), math.floatEpsAt(f64, 0x1.26abdc68d07aap+1));
    try testing.expectApproxEqAbs(0x1.d85a44ea44fe4p+0, acosBinary64(-0x1.15679e27084ddp-2), math.floatEpsAt(f64, 0x1.d85a44ea44fe4p+0));
    try testing.expectApproxEqAbs(0x1.9c2f688eee8abp+0, acosBinary64(-0x1.41e131b093c41p-5), math.floatEpsAt(f64, 0x1.9c2f688eee8abp+0));
    try testing.expectApproxEqAbs(0x1.e881b1d4eb2a1p-1, acosBinary64(0x1.281b0d18455f5p-1), math.floatEpsAt(f64, 0x1.e881b1d4eb2a1p-1));
    try testing.expectApproxEqAbs(0x1.1713f567a87efp-1, acosBinary64(0x1.b5ce34a51b239p-1), math.floatEpsAt(f64, 0x1.1713f567a87efp-1));
    try testing.expectApproxEqAbs(0x1.bd5acbe8fcc59p+0, acosBinary64(-0x1.583481079de4dp-3), math.floatEpsAt(f64, 0x1.bd5acbe8fcc59p+0));
    try testing.expectApproxEqAbs(0x1.6ce7d66f628e5p+1, acosBinary64(-0x1.ea8223103b871p-1), math.floatEpsAt(f64, 0x1.6ce7d66f628e5p+1));
}

test "acosExtended80.special" {
    try testing.expectApproxEqAbs(0x1.921fb54442d1846ap+0, acosExtended80(0x0p+0), math.floatEpsAt(f80, 0x1.921fb54442d1846ap+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d1846ap+1, acosExtended80(-0x1p+0), math.floatEpsAt(f80, 0x1.921fb54442d1846ap+1));
    try testing.expectEqual(0x0p+0, acosExtended80(0x1p+0));
    try testing.expect(math.isNan(acosExtended80(0x1.0000000000000002p+0)));
    try testing.expect(math.isNan(acosExtended80(-0x1.0000000000000002p+0)));
    try testing.expect(math.isNan(acosExtended80(math.inf(f80))));
    try testing.expect(math.isNan(acosExtended80(-math.inf(f80))));
    try testing.expect(math.isNan(acosExtended80(math.nan(f80))));
}

test "acosExtended80" {
    try testing.expectApproxEqAbs(0x1.86b349040d28f794p-1, acosExtended80(0x1.72068a321edc8804p-1), math.floatEpsAt(f80, 0x1.86b349040d28f794p-1));
    try testing.expectApproxEqAbs(0x1.d4923ade73ec379cp0, acosExtended80(-0x1.06d0a467d22977ecp-2), math.floatEpsAt(f80, 0x1.d4923ade73ec379cp0));
    try testing.expectApproxEqAbs(0x1.62e0e8898c6d04f2p0, acosExtended80(0x1.77d21385faa9798ap-3), math.floatEpsAt(f80, 0x1.62e0e8898c6d04f2p0));
    try testing.expectApproxEqAbs(0x1.3123cbcd5dc4bd58p1, acosExtended80(-0x1.73ee3e8bc2a44dbep-1), math.floatEpsAt(f80, 0x1.3123cbcd5dc4bd58p1));
    try testing.expectApproxEqAbs(0x1.062a6d562df2d316p0, acosExtended80(0x1.0a2dd1f6ffcf668ap-1), math.floatEpsAt(f80, 0x1.062a6d562df2d316p0));
    try testing.expectApproxEqAbs(0x1.5ffd68b520aa55fap0, acosExtended80(0x1.8e835c490a3aff9ep-3), math.floatEpsAt(f80, 0x1.5ffd68b520aa55fap0));
    try testing.expectApproxEqAbs(0x1.5bfe6cabda700684p0, acosExtended80(0x1.add20cdc1565064cp-3), math.floatEpsAt(f80, 0x1.5bfe6cabda700684p0));
    try testing.expectApproxEqAbs(0x1.90fe1c993b571924p0, acosExtended80(0x1.21986d43727fca72p-8), math.floatEpsAt(f80, 0x1.90fe1c993b571924p0));
    try testing.expectApproxEqAbs(0x1.18044ccc626e7f9ep0, acosExtended80(0x1.d61e0b3fae6a0564p-2), math.floatEpsAt(f80, 0x1.18044ccc626e7f9ep0));
    try testing.expectApproxEqAbs(0x1.a39513b6c16532b4p0, acosExtended80(-0x1.171e7c4a41883ccap-4), math.floatEpsAt(f80, 0x1.a39513b6c16532b4p0));
}

test "acosBinary128.special" {
    try testing.expectApproxEqAbs(0x1.921fb54442d18469898cc51701b8p0, acosBinary128(0x0p+0), math.floatEpsAt(f128, 0x1.921fb54442d18469898cc51701b8p0));
    try testing.expectApproxEqAbs(0x1.921fb54442d18469898cc51701b8p1, acosBinary128(-0x1p+0), math.floatEpsAt(f128, 0x1.921fb54442d18469898cc51701b8p1));
    try testing.expectEqual(0x0p+0, acosBinary128(0x1p+0));
    try testing.expect(math.isNan(acosBinary128(0x1.0000000000000000000000000001p0)));
    try testing.expect(math.isNan(acosBinary128(-0x1.0000000000000000000000000001p0)));
    try testing.expect(math.isNan(acosBinary128(math.inf(f128))));
    try testing.expect(math.isNan(acosBinary128(-math.inf(f128))));
    try testing.expect(math.isNan(acosBinary128(math.nan(f128))));
}

test "acosBinary128" {
    try testing.expectApproxEqAbs(0x1.250e9a58f049eeafa99db4360c88p1, acosBinary128(-0x1.511bdb99a3c4373bedf834ef4f68p-1), math.floatEpsAt(f128, 0x1.250e9a58f049eeafa99db4360c88p1));
    try testing.expectApproxEqAbs(0x1.2786664b1c676c99437b68590004p1, acosBinary128(-0x1.5879cc3ad6dfd2a52e9891c69808p-1), math.floatEpsAt(f128, 0x1.2786664b1c676c99437b68590004p1));
    try testing.expectApproxEqAbs(0x1.cb190cd361c7c03a09c470b4caebp-1, acosBinary128(0x1.3f988ba64a7eb97a751c5f0b3077p-1), math.floatEpsAt(f128, 0x1.cb190cd361c7c03a09c470b4caebp-1));
    try testing.expectApproxEqAbs(0x1.1f373be697880111758f582b1a96p1, acosBinary128(-0x1.3f2d96c7768e4c4fa02315727959p-1), math.floatEpsAt(f128, 0x1.1f373be697880111758f582b1a96p1));
    try testing.expectApproxEqAbs(0x1.0d92fd2a0a6ca3e4853c1de9ea6ap0, acosBinary128(0x1.fad303c2e28c1f4d8f9fd0e5686fp-2), math.floatEpsAt(f128, 0x1.0d92fd2a0a6ca3e4853c1de9ea6ap0));
    try testing.expectApproxEqAbs(0x1.15d4b306e16fbf9ea4f29e82b154p0, acosBinary128(0x1.ddde322bd1a2ee50c5ba30c9c617p-2), math.floatEpsAt(f128, 0x1.15d4b306e16fbf9ea4f29e82b154p0));
    try testing.expectApproxEqAbs(0x1.49b0a0355a5539052388e8a6dc11p1, acosBinary128(-0x1.b02f6adefcbeb1d48666b827ff17p-1), math.floatEpsAt(f128, 0x1.49b0a0355a5539052388e8a6dc11p1));
    try testing.expectApproxEqAbs(0x1.1be0b757f4cef022f5d2422b9c78p0, acosBinary128(0x1.c8581cce7cd3f6efab0fc60d9b7dp-2), math.floatEpsAt(f128, 0x1.1be0b757f4cef022f5d2422b9c78p0));
    try testing.expectApproxEqAbs(0x1.513270e671db2d840f20b0186c2cp1, acosBinary128(-0x1.bf887b8c4e33cbef59993056f3dep-1), math.floatEpsAt(f128, 0x1.513270e671db2d840f20b0186c2cp1));
    try testing.expectApproxEqAbs(0x1.70851a509f0e8bfbe780aa8f29f9p0, acosBinary128(0x1.0c0f600ab6f9c84c6102942044cep-3), math.floatEpsAt(f128, 0x1.70851a509f0e8bfbe780aa8f29f9p0));
}

fn acosBinary32Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f32)) @TypeOf(x) {
    const pi: @Vector(vec_len, f32) = @splat(math.pi);
    const pi_over_2: @Vector(vec_len, f32) = @splat(math.pi / 2.0);
    const zero: @Vector(vec_len, f32) = @splat(0.0);
    const half: @Vector(vec_len, f32) = @splat(0.5);
    const neg_one: @Vector(vec_len, f32) = @splat(-1.0);
    const two: @Vector(vec_len, f32) = @splat(2.0);
    const c0: @Vector(vec_len, f32) = @splat(0x1.55555ep-3);
    const c1: @Vector(vec_len, f32) = @splat(0x1.33261ap-4);
    const c2: @Vector(vec_len, f32) = @splat(0x1.70d7dcp-5);
    const c3: @Vector(vec_len, f32) = @splat(0x1.b059dp-6);
    const c4: @Vector(vec_len, f32) = @splat(0x1.3af7d8p-5);

    const ax = @abs(x);
    const ax_lt_half = ax < half;
    const is_neg = x < zero;
    const z2 = @select(f32, ax_lt_half, x * x, @mulAdd(@Vector(vec_len, f32), -half, ax, half));
    const z = @select(f32, ax_lt_half, ax, @sqrt(z2));
    const z3 = z2 * z;
    const p3_4 = @mulAdd(@Vector(vec_len, f32), z2, c4, c3);
    const p2_4 = @mulAdd(@Vector(vec_len, f32), z2, p3_4, c2);
    const p1_4 = @mulAdd(@Vector(vec_len, f32), z2, p2_4, c1);
    const p0_4 = @mulAdd(@Vector(vec_len, f32), z2, p1_4, c0);
    const p = @mulAdd(@Vector(vec_len, f32), z3, p0_4, z);
    const mul = @select(f32, ax_lt_half, neg_one, two);
    const add = @select(f32, ax_lt_half, pi_over_2, @select(f32, is_neg, pi, zero));
    return @mulAdd(@Vector(vec_len, f32), mul, @select(f32, is_neg, -p, p), add);
}

fn acosBinary64Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f64)) @TypeOf(x) {
    const pi: @Vector(vec_len, f64) = @splat(math.pi);
    const pi_over_2: @Vector(vec_len, f64) = @splat(math.pi / 2.0);
    const zero: @Vector(vec_len, f64) = @splat(0.0);
    const half: @Vector(vec_len, f64) = @splat(0.5);
    const neg_one: @Vector(vec_len, f64) = @splat(-1.0);
    const two: @Vector(vec_len, f64) = @splat(2.0);
    const c0: @Vector(vec_len, f64) = @splat(0x1.555555555554ep-3);
    const c1: @Vector(vec_len, f64) = @splat(0x1.3333333337233p-4);
    const c2: @Vector(vec_len, f64) = @splat(0x1.6db6db67f6d9fp-5);
    const c3: @Vector(vec_len, f64) = @splat(0x1.f1c71fbd29fbbp-6);
    const c4: @Vector(vec_len, f64) = @splat(0x1.6e8b264d467d6p-6);
    const c5: @Vector(vec_len, f64) = @splat(0x1.1c5997c357e9dp-6);
    const c6: @Vector(vec_len, f64) = @splat(0x1.c86a22cd9389dp-7);
    const c7: @Vector(vec_len, f64) = @splat(0x1.856073c22ebbep-7);
    const c8: @Vector(vec_len, f64) = @splat(0x1.fd1151acb6bedp-8);
    const c9: @Vector(vec_len, f64) = @splat(0x1.087182f799c1dp-6);
    const c10: @Vector(vec_len, f64) = @splat(-0x1.6602748120927p-7);
    const c11: @Vector(vec_len, f64) = @splat(0x1.cfa0dd1f9478p-6);

    const ax = @abs(x);
    const ax_lt_half = ax < half;
    const is_neg = x < zero;
    const z2 = @select(f64, ax_lt_half, x * x, @mulAdd(@Vector(vec_len, f64), -half, ax, half));
    const z = @select(f64, ax_lt_half, ax, @sqrt(z2));
    const z3 = z2 * z;
    const z4 = z2 * z2;
    const z8 = z4 * z4;
    const p0_1 = @mulAdd(@Vector(vec_len, f64), z2, c1, c0);
    const p2_3 = @mulAdd(@Vector(vec_len, f64), z2, c3, c2);
    const p0_3 = @mulAdd(@Vector(vec_len, f64), z4, p2_3, p0_1);
    const p4_5 = @mulAdd(@Vector(vec_len, f64), z2, c5, c4);
    const p6_7 = @mulAdd(@Vector(vec_len, f64), z2, c7, c6);
    const p4_7 = @mulAdd(@Vector(vec_len, f64), z4, p6_7, p4_5);
    const p8_9 = @mulAdd(@Vector(vec_len, f64), z2, c9, c8);
    const p10_11 = @mulAdd(@Vector(vec_len, f64), z2, c11, c10);
    const p8_11 = @mulAdd(@Vector(vec_len, f64), z4, p10_11, p8_9);
    const p4_11 = @mulAdd(@Vector(vec_len, f64), z8, p8_11, p4_7);
    const p0_11 = @mulAdd(@Vector(vec_len, f64), z8, p4_11, p0_3);
    const p = @mulAdd(@Vector(vec_len, f64), z3, p0_11, z);
    const mul = @select(f64, ax_lt_half, neg_one, two);
    const add = @select(f64, ax_lt_half, pi_over_2, @select(f64, is_neg, pi, zero));
    return @mulAdd(@Vector(vec_len, f64), mul, @select(f64, is_neg, -p, p), add);
}

test "acosBinary32Vec.special" {
    const input: @Vector(8, f32) = .{
        0x0p+0,
        -0x1p+0,
        0x1p+0,
        0x1.000002p+0,
        -0x1.000002p+0,
        math.inf(f32),
        -math.inf(f32),
        math.nan(f32),
    };
    const output = acosBinary32Vec(8, input);
    try testing.expectApproxEqAbs(0x1.921fb6p+0, output[0], math.floatEpsAt(f32, 0x1.921fb6p+0));
    try testing.expectApproxEqAbs(0x1.921fb6p+1, output[1], math.floatEpsAt(f32, 0x1.921fb6p+1));
    try testing.expectEqual(0x0p+0, output[2]);
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
    try testing.expect(math.isNan(output[5]));
    try testing.expect(math.isNan(output[6]));
    try testing.expect(math.isNan(output[7]));
}

test "acosBinary32Vec" {
    const input: @Vector(10, f32) = .{
        -0x1.13284cp-2,
        0x1.6ca8ep-1,
        0x1.c2ca6p-1,
        -0x1.55f12p-1,
        -0x1.15679ep-2,
        -0x1.41e132p-5,
        0x1.281b0ep-1,
        0x1.b5ce34p-1,
        -0x1.583482p-3,
        -0x1.ea8224p-1,
    };
    const output = acosBinary32Vec(10, input);
    try testing.expectApproxEqAbs(0x1.d7c4e6p+0, output[0], math.floatEpsAt(f32, 0x1.d7c4e6p+0));
    try testing.expectApproxEqAbs(0x1.8e6756p-1, output[1], math.floatEpsAt(f32, 0x1.8e6756p-1));
    try testing.expectApproxEqAbs(0x1.f9d74cp-2, output[2], math.floatEpsAt(f32, 0x1.f9d74cp-2));
    try testing.expectApproxEqAbs(0x1.26abdcp+1, output[3], math.floatEpsAt(f32, 0x1.26abdcp+1));
    try testing.expectApproxEqAbs(0x1.d85a44p+0, output[4], math.floatEpsAt(f32, 0x1.d85a44p+0));
    try testing.expectApproxEqAbs(0x1.9c2f68p+0, output[5], math.floatEpsAt(f32, 0x1.9c2f68p+0));
    try testing.expectApproxEqAbs(0x1.e881bp-1, output[6], math.floatEpsAt(f32, 0x1.e881bp-1));
    try testing.expectApproxEqAbs(0x1.1713f6p-1, output[7], math.floatEpsAt(f32, 0x1.1713f6p-1));
    try testing.expectApproxEqAbs(0x1.bd5accp+0, output[8], math.floatEpsAt(f32, 0x1.bd5accp+0));
    try testing.expectApproxEqAbs(0x1.6ce7d8p+1, output[9], math.floatEpsAt(f32, 0x1.6ce7d8p+1));
}

test "acosBinary64Vec.special" {
    const input: @Vector(8, f64) = .{
        0x0p+0,
        -0x1p+0,
        0x1p+0,
        0x1.0000000000001p+0,
        -0x1.0000000000001p+0,
        math.inf(f64),
        -math.inf(f64),
        math.nan(f64),
    };
    const output = acosBinary64Vec(8, input);
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+0, output[0], math.floatEpsAt(f64, 0x1.921fb54442d18p+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+1, output[1], math.floatEpsAt(f64, 0x1.921fb54442d18p+1));
    try testing.expectEqual(0x0p+0, output[2]);
    try testing.expect(math.isNan(output[3]));
    try testing.expect(math.isNan(output[4]));
    try testing.expect(math.isNan(output[5]));
    try testing.expect(math.isNan(output[6]));
    try testing.expect(math.isNan(output[7]));
}

test "acosBinary64Vec" {
    const input: @Vector(10, f64) = .{
        -0x1.13284b2b5006dp-2,
        0x1.6ca8dfb825911p-1,
        0x1.c2ca609de7505p-1,
        -0x1.55f11fba96889p-1,
        -0x1.15679e27084ddp-2,
        -0x1.41e131b093c41p-5,
        0x1.281b0d18455f5p-1,
        0x1.b5ce34a51b239p-1,
        -0x1.583481079de4dp-3,
        -0x1.ea8223103b871p-1,
    };
    const output = acosBinary64Vec(10, input);
    try testing.expectApproxEqAbs(0x1.d7c4e61020905p+0, output[0], math.floatEpsAt(f64, 0x1.d7c4e61020905p+0));
    try testing.expectApproxEqAbs(0x1.8e6756e27c366p-1, output[1], math.floatEpsAt(f64, 0x1.8e6756e27c366p-1));
    try testing.expectApproxEqAbs(0x1.f9d748eaf956p-2, output[2], math.floatEpsAt(f64, 0x1.f9d748eaf956p-2));
    try testing.expectApproxEqAbs(0x1.26abdc68d07aap+1, output[3], math.floatEpsAt(f64, 0x1.26abdc68d07aap+1));
    try testing.expectApproxEqAbs(0x1.d85a44ea44fe4p+0, output[4], math.floatEpsAt(f64, 0x1.d85a44ea44fe4p+0));
    try testing.expectApproxEqAbs(0x1.9c2f688eee8abp+0, output[5], math.floatEpsAt(f64, 0x1.9c2f688eee8abp+0));
    try testing.expectApproxEqAbs(0x1.e881b1d4eb2a1p-1, output[6], math.floatEpsAt(f64, 0x1.e881b1d4eb2a1p-1));
    try testing.expectApproxEqAbs(0x1.1713f567a87efp-1, output[7], math.floatEpsAt(f64, 0x1.1713f567a87efp-1));
    try testing.expectApproxEqAbs(0x1.bd5acbe8fcc59p+0, output[8], math.floatEpsAt(f64, 0x1.bd5acbe8fcc59p+0));
    try testing.expectApproxEqAbs(0x1.6ce7d66f628e5p+1, output[9], math.floatEpsAt(f64, 0x1.6ce7d66f628e5p+1));
}
