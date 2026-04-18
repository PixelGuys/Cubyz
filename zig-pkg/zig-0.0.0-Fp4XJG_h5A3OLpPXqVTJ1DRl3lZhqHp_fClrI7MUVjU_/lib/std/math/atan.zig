// Ported from musl, which is licensed under the MIT license:
// https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
//
// https://git.musl-libc.org/cgit/musl/tree/src/math/atanf.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/atan.c
// https://git.musl-libc.org/cgit/musl/tree/src/math/atanl.c
//
// Ported from ARM-software, which is licensed under the MIT license:
// https://github.com/ARM-software/optimized-routines/blob/master/LICENSE
//
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/atanf.c
// https://github.com/ARM-software/optimized-routines/blob/master/math/aarch64/advsimd/atan.c

const std = @import("../std.zig");
const math = std.math;
const mem = std.mem;
const testing = std.testing;

/// Returns the arc-tangent of x.
///
/// Special Cases:
///  - atan(+-0)   = +-0
///  - atan(+-inf) = +-pi/2
pub fn atan(x: anytype) @TypeOf(x) {
    const T = @TypeOf(x);
    switch (@typeInfo(T)) {
        .float => |info| switch (info.bits) {
            16 => return atanBinary16(x),
            32 => return atanBinary32(x),
            64 => return atanBinary64(x),
            80 => return atanExtended80(x),
            128 => return atanBinary128(x),
            else => comptime unreachable,
        },
        .vector => |info| switch (info.child) {
            f32 => return atanBinary32Vec(info.len, x),
            f64 => return atanBinary64Vec(info.len, x),
            else => @compileError("unimplemented"),
        },
        else => comptime unreachable,
    }
}

fn atanBinary16(x: f16) f16 {
    const atanhi: []const f32 = &.{
        4.6364760399e-01, // atan(0.5)hi 0x3eed6338
        7.8539812565e-01, // atan(1.0)hi 0x3f490fda
        9.8279368877e-01, // atan(1.5)hi 0x3f7b985e
        1.5707962513e+00, // atan(inf)hi 0x3fc90fda
    };
    const aT: []const f32 = &.{
        0x1.fffcccp-1,
        -0x1.52e8ccp-2,
        0x1.522336p-3,
    };

    const hx: u16 = @bitCast(x);
    const ix = hx & 0x7fff;
    const sign = (hx >> 15) != 0;
    // if |x| >= 2^11
    if (ix >= 0x6800) {
        if (math.isNan(x)) {
            return x;
        }
        const z = atanhi[3] + 0x1p-120;
        return @floatCast(if (sign) -z else z);
    }
    const x_: f32, const id: ?usize = blk: {
        // |x| < 0.4375
        if (ix < 0x3700) {
            // |x| < 2^(-6)
            if (ix < 0x2400) {
                if (ix < 0x400) {
                    // raise underflow for subnormal x
                    mem.doNotOptimizeAway(x * x);
                }
                return x;
            }
            break :blk .{ @floatCast(x), null };
        } else {
            const x_: f32 = @floatCast(@abs(x));
            // |x| < 1.1875
            if (ix < 0x3cc0) {
                // 7/16 <= |x| < 11/16
                if (ix < 0x3980) {
                    break :blk .{ (2.0 * x_ - 1.0) / (2.0 + x_), 0 };
                }
                // 11/16 <= |x| < 19/16
                else {
                    break :blk .{ (x_ - 1.0) / (x_ + 1.0), 1 };
                }
            } else {
                // |x| < 2.4375
                if (ix < 0x40e0) {
                    break :blk .{ (x_ - 1.5) / (1.0 + 1.5 * x_), 2 };
                }
                // 2.4375 <= |x| < 2^11
                else {
                    break :blk .{ -1.0 / x_, 3 };
                }
            }
        }
    };
    // end of argument reduction
    const z = x_ * x_;
    const s = aT[0] + z * (aT[1] + z * aT[2]);
    if (id) |id_| {
        const z_ = atanhi[id_] + x_ * s;
        return @floatCast(if (sign) -z_ else z_);
    } else {
        return @floatCast(x_ * s);
    }
}

fn atanBinary32(x: f32) f32 {
    const atanhi: []const f32 = &.{
        4.6364760399e-01, // atan(0.5)hi 0x3eed6338
        7.8539812565e-01, // atan(1.0)hi 0x3f490fda
        9.8279368877e-01, // atan(1.5)hi 0x3f7b985e
        1.5707962513e+00, // atan(inf)hi 0x3fc90fda
    };
    const atanlo: []const f32 = &.{
        5.0121582440e-09, // atan(0.5)lo 0x31ac3769
        3.7748947079e-08, // atan(1.0)lo 0x33222168
        3.4473217170e-08, // atan(1.5)lo 0x33140fb4
        7.5497894159e-08, // atan(inf)lo 0x33a22168
    };
    const aT: []const f32 = &.{
        3.3333328366e-01,
        -1.9999158382e-01,
        1.4253635705e-01,
        -1.0648017377e-01,
        6.1687607318e-02,
    };

    const hx: u32 = @bitCast(x);
    const ix = hx & 0x7fff_ffff;
    const sign = (hx >> 31) != 0;
    // if |x| >= 2^26
    if (ix >= 0x4c80_0000) {
        if (math.isNan(x)) {
            return x;
        }
        const z = atanhi[3] + 0x1p-120;
        return if (sign) -z else z;
    }
    const x_, const id: ?usize = blk: {
        // |x| < 0.4375
        if (ix < 0x3ee00000) {
            // |x| < 2^(-12)
            if (ix < 0x39800000) {
                if (ix < 0x00800000) {
                    // raise underflow for subnormal x
                    mem.doNotOptimizeAway(x * x);
                }
                return x;
            }
            break :blk .{ x, null };
        } else {
            const x_ = @abs(x);
            // |x| < 1.1875
            if (ix < 0x3f98_0000) {
                // 7/16 <= |x| < 11/16
                if (ix < 0x3f30_0000) {
                    break :blk .{ (2.0 * x_ - 1.0) / (2.0 + x_), 0 };
                }
                // 11/16 <= |x| < 19/16
                else {
                    break :blk .{ (x_ - 1.0) / (x_ + 1.0), 1 };
                }
            } else {
                // |x| < 2.4375
                if (ix < 0x401c_0000) {
                    break :blk .{ (x_ - 1.5) / (1.0 + 1.5 * x_), 2 };
                }
                // 2.4375 <= |x| < 2^26
                else {
                    break :blk .{ -1.0 / x_, 3 };
                }
            }
        }
    };
    // end of argument reduction
    const z = x_ * x_;
    const w = z * z;
    // break sum from i=0 to 10 aT[i]z^(i+1) into odd and even poly
    const s1 = z * (aT[0] + w * (aT[2] + w * aT[4]));
    const s2 = w * (aT[1] + w * aT[3]);
    if (id) |id_| {
        const z_ = atanhi[id_] - ((x_ * (s1 + s2) - atanlo[id_]) - x_);
        return if (sign) -z_ else z_;
    } else {
        return x_ - x_ * (s1 + s2);
    }
}

fn atanBinary64(x: f64) f64 {
    const atanhi: []const f64 = &.{
        4.63647609000806093515e-01, // atan(0.5)hi 0x3FDDAC67, 0x0561BB4F
        7.85398163397448278999e-01, // atan(1.0)hi 0x3FE921FB, 0x54442D18
        9.82793723247329054082e-01, // atan(1.5)hi 0x3FEF730B, 0xD281F69B
        1.57079632679489655800e+00, // atan(inf)hi 0x3FF921FB, 0x54442D18
    };
    const atanlo: []const f64 = &.{
        2.26987774529616870924e-17, // atan(0.5)lo 0x3C7A2B7F, 0x222F65E2
        3.06161699786838301793e-17, // atan(1.0)lo 0x3C81A626, 0x33145C07
        1.39033110312309984516e-17, // atan(1.5)lo 0x3C700788, 0x7AF0CBBD
        6.12323399573676603587e-17, // atan(inf)lo 0x3C91A626, 0x33145C07
    };
    const aT: []const f64 = &.{
        3.33333333333329318027e-01, // 0x3FD55555, 0x5555550D
        -1.99999999998764832476e-01, // 0xBFC99999, 0x9998EBC4
        1.42857142725034663711e-01, // 0x3FC24924, 0x920083FF
        -1.11111104054623557880e-01, // 0xBFBC71C6, 0xFE231671
        9.09088713343650656196e-02, // 0x3FB745CD, 0xC54C206E
        -7.69187620504482999495e-02, // 0xBFB3B0F2, 0xAF749A6D
        6.66107313738753120669e-02, // 0x3FB10D66, 0xA0D03D51
        -5.83357013379057348645e-02, // 0xBFADDE2D, 0x52DEFD9A
        4.97687799461593236017e-02, // 0x3FA97B4B, 0x24760DEB
        -3.65315727442169155270e-02, // 0xBFA2B444, 0x2C6A6C2F
        1.62858201153657823623e-02, // 0x3F90AD3A, 0xE322DA11
    };

    const hx: u64 = @bitCast(x);
    const ix: u32 = @truncate((hx >> 32) & 0x7fffffff);
    const sign = (hx >> 63) != 0;
    // if |x| >= 2^66
    if (ix >= 0x44100000) {
        if (math.isNan(x)) {
            return x;
        }
        const z = atanhi[3] + 0x1p-120;
        return if (sign) -z else z;
    }
    const x_, const id: ?usize = blk: {
        // |x| < 0.4375
        if (ix < 0x3fdc_0000) {
            // |x| < 2^(-27)
            if (ix < 0x3e40_0000) {
                if (ix < 0x0010_0000) {
                    // raise underflow for subnormal x
                    mem.doNotOptimizeAway(@as(f32, @floatCast(x)));
                }
                return x;
            }
            break :blk .{ x, null };
        } else {
            const x_ = @abs(x);
            // |x| < 1.1875
            if (ix < 0x3ff3_0000) {
                // 7/16 <= |x| < 11/16
                if (ix < 0x3fe6_0000) {
                    break :blk .{ (2.0 * x_ - 1.0) / (2.0 + x_), 0 };
                }
                // 11/16 <= |x| < 19/16
                else {
                    break :blk .{ (x_ - 1.0) / (x_ + 1.0), 1 };
                }
            } else {
                // |x| < 2.4375
                if (ix < 0x4003_8000) {
                    break :blk .{ (x_ - 1.5) / (1.0 + 1.5 * x_), 2 };
                }
                // 2.4375 <= |x| < 2^66
                else {
                    break :blk .{ -1.0 / x_, 3 };
                }
            }
        }
    };
    // end of argument reduction
    const z = x_ * x_;
    const w = z * z;
    // break sum from i=0 to 10 aT[i]z^(i+1) into odd and even poly
    const s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * aT[10])))));
    const s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * aT[9]))));
    if (id) |id_| {
        const z_ = atanhi[id_] - (x_ * (s1 + s2) - atanlo[id_] - x_);
        return if (sign) -z_ else z_;
    } else {
        return x_ - x_ * (s1 + s2);
    }
}

fn atanExtended80(x: f80) f80 {
    const atanhi: []const f80 = &.{
        4.63647609000806116202e-01,
        7.85398163397448309628e-01,
        9.82793723247329067960e-01,
        1.57079632679489661926e+00,
    };
    const atanlo: []const f80 = &.{
        1.18469937025062860669e-20,
        -1.25413940316708300586e-20,
        2.55232234165405176172e-20,
        -2.50827880633416601173e-20,
    };
    const aT: []const f80 = &.{
        3.33333333333333333017e-01,
        -1.99999999999999632011e-01,
        1.42857142857046531280e-01,
        -1.11111111100562372733e-01,
        9.09090902935647302252e-02,
        -7.69230552476207730353e-02,
        6.66661718042406260546e-02,
        -5.88158892835030888692e-02,
        5.25499891539726639379e-02,
        -4.70119845393155721494e-02,
        4.03539201366454414072e-02,
        -2.91303858419364158725e-02,
        1.24822046299269234080e-02,
    };

    const hx: u80 = @bitCast(x);
    const se: u16 = @truncate(hx >> 64);
    const e = se & 0x7fff;
    const sign = se >> 15 != 0;
    // if |x| is large, atan(x)~=pi/2
    if (e >= 0x3fff + math.floatMantissaBits(f80) + 1) {
        if (math.isNan(x)) {
            return x;
        }
        return if (sign) -atanhi[3] else atanhi[3];
    }
    // Extract the exponent and the first few bits of the mantissa.
    const m: u64 = @truncate(hx & 0x0000_ffff_ffff_ffff_ffff);
    const expman = ((@as(u32, @intCast(se)) & 0x7fff) << 8) | (@as(u32, @truncate(m >> 55)) & 0xff);
    const x_, const id: ?usize = blk: {
        // |x| < 0.4375
        if (expman < ((0x3fff - 2) << 8) + 0xc0) {
            // if |x| is small, atanl(x)~=x
            if (e < 0x3fff - (math.floatMantissaBits(f80) + 1) / 2) {
                // raise underflow if subnormal
                if (e == 0) {
                    std.mem.doNotOptimizeAway(@as(f32, @floatCast(x)));
                }
                return x;
            }
            break :blk .{ x, null };
        } else {
            const x_ = @abs(x);
            // |x| < 1.1875
            if (expman < (0x3fff << 8) + 0x30) {
                // 7/16 <= |x| < 11/16
                if (expman < ((0x3fff - 1) << 8) + 0x60) {
                    break :blk .{ (2.0 * x_ - 1.0) / (2.0 + x_), 0 };
                }
                // 11/16 <= |x| < 19/16
                else {
                    break :blk .{ (x_ - 1.0) / (x_ + 1.0), 1 };
                }
            } else {
                // |x| < 2.4375
                if (expman < ((0x3fff + 1) << 8) + 0x38) {
                    break :blk .{ (x_ - 1.5) / (1.0 + 1.5 * x_), 2 };
                }
                // 2.4375 <= |x|
                else {
                    break :blk .{ -1.0 / x_, 3 };
                }
            }
        }
    };
    // end of argument reduction
    const z = x_ * x_;
    const w = z * z;
    // break sum aT[i]z^(i+1) into odd and even poly
    const s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * (aT[10] + w * aT[12]))))));
    const s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * (aT[9] + w * aT[11])))));
    if (id) |id_| {
        const z_ = atanhi[id_] - ((x_ * (s1 + s2) - atanlo[id_]) - x_);
        return if (sign) -z_ else z_;
    } else {
        return x_ - x_ * (s1 + s2);
    }
}

fn atanBinary128(x: f128) f128 {
    const atanhi: []const f128 = &.{
        4.63647609000806116214256231461214397e-01,
        7.85398163397448309615660845819875699e-01,
        9.82793723247329067985710611014666038e-01,
        1.57079632679489661923132169163975140e+00,
    };
    const atanlo: []const f128 = &.{
        4.89509642257333492668618435220297706e-36,
        2.16795253253094525619926100651083806e-35,
        -2.31288434538183565909319952098066272e-35,
        4.33590506506189051239852201302167613e-35,
    };
    const aT: []const f128 = &.{
        3.33333333333333333333333333333333125e-01,
        -1.99999999999999999999999999999180430e-01,
        1.42857142857142857142857142125269827e-01,
        -1.11111111111111111111110834490810169e-01,
        9.09090909090909090908522355708623681e-02,
        -7.69230769230769230696553844935357021e-02,
        6.66666666666666660390096773046256096e-02,
        -5.88235294117646671706582985209643694e-02,
        5.26315789473666478515847092020327506e-02,
        -4.76190476189855517021024424991436144e-02,
        4.34782608678695085948531993458097026e-02,
        -3.99999999632663469330634215991142368e-02,
        3.70370363987423702891250829918659723e-02,
        -3.44827496515048090726669907612335954e-02,
        3.22579620681420149871973710852268528e-02,
        -3.03020767654269261041647570626778067e-02,
        2.85641979882534783223403715930946138e-02,
        -2.69824879726738568189929461383741323e-02,
        2.54194698498808542954187110873675769e-02,
        -2.35083879708189059926183138130183215e-02,
        2.04832358998165364349957325067131428e-02,
        -1.54489555488544397858507248612362957e-02,
        8.64492360989278761493037861575248038e-03,
        -2.58521121597609872727919154569765469e-03,
    };

    const hx: u128 = @bitCast(x);
    const se: u16 = @truncate(hx >> 112);
    const e = se & 0x7fff;
    const sign = se >> 15 != 0;
    // if |x| is large, atan(x)~=pi/2
    if (e >= 0x3fff + math.floatMantissaBits(f128) + 2) {
        if (math.isNan(x)) {
            return x;
        }
        return if (sign) -atanhi[3] else atanhi[3];
    }
    // Extract the exponent and the first few bits of the mantissa.
    const top: u16 = @truncate((hx >> 96) & 0x0000_ffff);
    const expman = ((@as(u32, @intCast(se)) & 0x7fff) << 8) | (@as(u32, @intCast(top)) >> 8);
    const x_, const id: ?usize = blk: {
        // |x| < 0.4375
        if (expman < ((0x3fff - 2) << 8) + 0xc0) {
            // if |x| is small, atanl(x)~=x
            if (e < 0x3fff - (math.floatMantissaBits(f128) + 2) / 2) {
                // raise underflow if subnormal
                if (e == 0) {
                    mem.doNotOptimizeAway(@as(f32, @floatCast(x)));
                }
                return x;
            }
            break :blk .{ x, null };
        } else {
            const x_ = @abs(x);
            // |x| < 1.1875
            if (expman < (0x3fff << 8) + 0x30) {
                // 7/16 <= |x| < 11/16
                if (expman < ((0x3fff - 1) << 8) + 0x60) {
                    break :blk .{ (2.0 * x_ - 1.0) / (2.0 + x_), 0 };
                }
                // 11/16 <= |x| < 19/16
                else {
                    break :blk .{ (x_ - 1.0) / (x_ + 1.0), 1 };
                }
            } else {
                // |x| < 2.4375
                if (expman < ((0x3fff + 1) << 8) + 0x38) {
                    break :blk .{ (x_ - 1.5) / (1.0 + 1.5 * x_), 2 };
                }
                // 2.4375 <= |x|
                else {
                    break :blk .{ -1.0 / x_, 3 };
                }
            }
        }
    };
    // end of argument reduction
    const z = x_ * x_;
    const w = z * z;
    // break sum aT[i]z^(i+1) into odd and even poly
    const s1 = z * (aT[0] + w * (aT[2] + w * (aT[4] + w * (aT[6] + w * (aT[8] + w * (aT[10] + w * (aT[12] + w * (aT[14] + w * (aT[16] + w * (aT[18] + w * (aT[20] + w * aT[22])))))))))));
    const s2 = w * (aT[1] + w * (aT[3] + w * (aT[5] + w * (aT[7] + w * (aT[9] + w * (aT[11] + w * (aT[13] + w * (aT[15] + w * (aT[17] + w * (aT[19] + w * (aT[21] + w * aT[23])))))))))));
    if (id) |id_| {
        const z_ = atanhi[id_] - ((x_ * (s1 + s2) - atanlo[id_]) - x_);
        return if (sign) -z_ else z_;
    } else {
        return x_ - x_ * (s1 + s2);
    }
}

test "atanBinary16.special" {
    try testing.expectEqual(0x0p+0, atanBinary16(0x0p+0));
    try testing.expectEqual(-0x0p+0, atanBinary16(-0x0p+0));
    try testing.expectApproxEqAbs(0x1.92p-1, atanBinary16(0x1p+0), math.floatEpsAt(f16, 0x1.92p-1));
    try testing.expectApproxEqAbs(-0x1.92p-1, atanBinary16(-0x1p+0), math.floatEpsAt(f16, -0x1.92p-1));
    try testing.expectApproxEqAbs(0x1.92p0, atanBinary16(math.inf(f16)), math.floatEpsAt(f16, 0x1.92p0));
    try testing.expectApproxEqAbs(-0x1.92p0, atanBinary16(-math.inf(f16)), math.floatEpsAt(f16, -0x1.92p0));
    try testing.expect(math.isNan(atanBinary16(math.nan(f16))));
}

test "atanBinary16" {
    try testing.expectApproxEqAbs(-0x1.74cp-2, atanBinary16(-0x1.864p-2), math.floatEpsAt(f16, -0x1.74cp-2));
    try testing.expectApproxEqAbs(-0x1.374p0, atanBinary16(-0x1.59cp1), math.floatEpsAt(f16, -0x1.374p0));
    try testing.expectApproxEqAbs(-0x1.11cp0, atanBinary16(-0x1.d2cp0), math.floatEpsAt(f16, -0x1.11cp0));
    try testing.expectApproxEqAbs(-0x1.33cp-1, atanBinary16(-0x1.5f4p-1), math.floatEpsAt(f16, -0x1.33cp-1));
    try testing.expectApproxEqAbs(0x1.37p0, atanBinary16(0x1.588p1), math.floatEpsAt(f16, 0x1.37p0));
    try testing.expectApproxEqAbs(-0x1.99cp-2, atanBinary16(-0x1.b14p-2), math.floatEpsAt(f16, -0x1.99cp-2));
    try testing.expectApproxEqAbs(0x1.2fcp0, atanBinary16(0x1.3ccp1), math.floatEpsAt(f16, 0x1.2fcp0));
    try testing.expectApproxEqAbs(-0x1.08cp-2, atanBinary16(-0x1.0ecp-2), math.floatEpsAt(f16, -0x1.08cp-2));
    try testing.expectApproxEqAbs(0x1.2ap0, atanBinary16(0x1.298p1), math.floatEpsAt(f16, 0x1.2ap0));
    try testing.expectApproxEqAbs(-0x1.1c8p0, atanBinary16(-0x1.028p1), math.floatEpsAt(f16, -0x1.1c8p0));
}

test "atanBinary32.special" {
    try testing.expectEqual(0x0p+0, atanBinary32(0x0p+0));
    try testing.expectEqual(-0x0p+0, atanBinary32(-0x0p+0));
    try testing.expectApproxEqAbs(0x1.921fb6p-1, atanBinary32(0x1p+0), math.floatEpsAt(f32, 0x1.921fb6p-1));
    try testing.expectApproxEqAbs(-0x1.921fb6p-1, atanBinary32(-0x1p+0), math.floatEpsAt(f32, -0x1.921fb6p-1));
    try testing.expectApproxEqAbs(0x1.921fb6p+0, atanBinary32(math.inf(f32)), math.floatEpsAt(f32, 0x1.921fb6p+0));
    try testing.expectApproxEqAbs(-0x1.921fb6p+0, atanBinary32(-math.inf(f32)), math.floatEpsAt(f32, -0x1.921fb6p+0));
    try testing.expect(math.isNan(atanBinary32(math.nan(f32))));
}

test "atanBinary32" {
    try testing.expectApproxEqAbs(-0x1.74c62p-2, atanBinary32(-0x1.8629dp-2), math.floatEpsAt(f32, -0x1.74c62p-2));
    try testing.expectApproxEqAbs(-0x1.375fd8p0, atanBinary32(-0x1.59d42ep1), math.floatEpsAt(f32, -0x1.375fd8p0));
    try testing.expectApproxEqAbs(-0x1.11b8aep0, atanBinary32(-0x1.d2dbe2p0), math.floatEpsAt(f32, -0x1.11b8aep0));
    try testing.expectApproxEqAbs(-0x1.33d28cp-1, atanBinary32(-0x1.5f314ep-1), math.floatEpsAt(f32, -0x1.33d28cp-1));
    try testing.expectApproxEqAbs(0x1.37082ep0, atanBinary32(0x1.5869bp1), math.floatEpsAt(f32, 0x1.37082ep0));
    try testing.expectApproxEqAbs(-0x1.99d7cap-2, atanBinary32(-0x1.b13a06p-2), math.floatEpsAt(f32, -0x1.99d7cap-2));
    try testing.expectApproxEqAbs(0x1.2fcb12p0, atanBinary32(0x1.3cb0f2p1), math.floatEpsAt(f32, 0x1.2fcb12p0));
    try testing.expectApproxEqAbs(-0x1.08c71ap-2, atanBinary32(-0x1.0ed746p-2), math.floatEpsAt(f32, -0x1.08c71ap-2));
    try testing.expectApproxEqAbs(0x1.2a24e2p0, atanBinary32(0x1.299d54p1), math.floatEpsAt(f32, 0x1.2a24e2p0));
    try testing.expectApproxEqAbs(-0x1.1c6178p0, atanBinary32(-0x1.0264fcp1), math.floatEpsAt(f32, -0x1.1c6178p0));
}

test "atanBinary64.special" {
    try testing.expectEqual(0x0p+0, atanBinary64(0x0p+0));
    try testing.expectEqual(-0x0p+0, atanBinary64(-0x0p+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d18p-1, atanBinary64(0x1p+0), math.floatEpsAt(f64, 0x1.921fb54442d18p-1));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18p-1, atanBinary64(-0x1p+0), math.floatEpsAt(f64, -0x1.921fb54442d18p-1));
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+0, atanBinary64(math.inf(f64)), math.floatEpsAt(f64, 0x1.921fb54442d18p+0));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18p+0, atanBinary64(-math.inf(f64)), math.floatEpsAt(f64, -0x1.921fb54442d18p+0));
    try testing.expect(math.isNan(atanBinary64(math.nan(f64))));
}

test "atanBinary64" {
    try testing.expectApproxEqAbs(-0x1.74c61f4377016p-2, atanBinary64(-0x1.8629d0244cdccp-2), math.floatEpsAt(f64, -0x1.74c61f4377016p-2));
    try testing.expectApproxEqAbs(-0x1.375fd7987cc2p0, atanBinary64(-0x1.59d42d4659937p1), math.floatEpsAt(f64, -0x1.375fd7987cc2p0));
    try testing.expectApproxEqAbs(-0x1.11b8adeba5616p0, atanBinary64(-0x1.d2dbe23d04f06p0), math.floatEpsAt(f64, -0x1.11b8adeba5616p0));
    try testing.expectApproxEqAbs(-0x1.33d28ca762539p-1, atanBinary64(-0x1.5f314e72398e8p-1), math.floatEpsAt(f64, -0x1.33d28ca762539p-1));
    try testing.expectApproxEqAbs(0x1.37082ce2dd03p0, atanBinary64(0x1.5869af37b7d08p1), math.floatEpsAt(f64, 0x1.37082ce2dd03p0));
    try testing.expectApproxEqAbs(-0x1.99d7cac66dd44p-2, atanBinary64(-0x1.b13a05a662618p-2), math.floatEpsAt(f64, -0x1.99d7cac66dd44p-2));
    try testing.expectApproxEqAbs(0x1.2fcb120468e8ep0, atanBinary64(0x1.3cb0f12f39d8ap1), math.floatEpsAt(f64, 0x1.2fcb120468e8ep0));
    try testing.expectApproxEqAbs(-0x1.08c71aa0e509p-2, atanBinary64(-0x1.0ed746b39cbb7p-2), math.floatEpsAt(f64, -0x1.08c71aa0e509p-2));
    try testing.expectApproxEqAbs(0x1.2a24e22d861dfp0, atanBinary64(0x1.299d54ac7d6bp1), math.floatEpsAt(f64, 0x1.2a24e22d861dfp0));
    try testing.expectApproxEqAbs(-0x1.1c617825f9751p0, atanBinary64(-0x1.0264fb9f3d50ep1), math.floatEpsAt(f64, -0x1.1c617825f9751p0));
}

test "atanExtended80.special" {
    try testing.expectEqual(0x0p+0, atanExtended80(0x0p+0));
    try testing.expectEqual(-0x0p+0, atanExtended80(-0x0p+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d1846ap-1, atanExtended80(0x1p+0), math.floatEpsAt(f80, 0x1.921fb54442d1846ap-1));
    try testing.expectApproxEqAbs(-0x1.921fb54442d1846ap-1, atanExtended80(-0x1p+0), math.floatEpsAt(f80, -0x1.921fb54442d1846ap-1));
    try testing.expectApproxEqAbs(0x1.921fb54442d1846ap0, atanExtended80(math.inf(f80)), math.floatEpsAt(f80, 0x1.921fb54442d1846ap0));
    try testing.expectApproxEqAbs(-0x1.921fb54442d1846ap0, atanExtended80(-math.inf(f80)), math.floatEpsAt(f80, -0x1.921fb54442d1846ap0));
    try testing.expect(math.isNan(atanExtended80(math.nan(f80))));
}

test "atanExtended80" {
    try testing.expectApproxEqAbs(-0x1.74c61f437701661p-2, atanExtended80(-0x1.8629d0244cdcbed8p-2), math.floatEpsAt(f80, -0x1.74c61f437701661p-2));
    try testing.expectApproxEqAbs(-0x1.375fd7987cc1fd02p0, atanExtended80(-0x1.59d42d4659936d9ep1), math.floatEpsAt(f80, -0x1.375fd7987cc1fd02p0));
    try testing.expectApproxEqAbs(-0x1.11b8adeba5615e04p0, atanExtended80(-0x1.d2dbe23d04f067b4p0), math.floatEpsAt(f80, -0x1.11b8adeba5615e04p0));
    try testing.expectApproxEqAbs(-0x1.33d28ca76253964cp-1, atanExtended80(-0x1.5f314e72398e7dbcp-1), math.floatEpsAt(f80, -0x1.33d28ca76253964cp-1));
    try testing.expectApproxEqAbs(0x1.37082ce2dd03010cp0, atanExtended80(0x1.5869af37b7d078cap1), math.floatEpsAt(f80, 0x1.37082ce2dd03010cp0));
    try testing.expectApproxEqAbs(-0x1.99d7cac66dd4438p-2, atanExtended80(-0x1.b13a05a66261821ap-2), math.floatEpsAt(f80, -0x1.99d7cac66dd4438p-2));
    try testing.expectApproxEqAbs(0x1.2fcb120468e8d9ecp0, atanExtended80(0x1.3cb0f12f39d899cp1), math.floatEpsAt(f80, 0x1.2fcb120468e8d9ecp0));
    try testing.expectApproxEqAbs(-0x1.08c71aa0e5090998p-2, atanExtended80(-0x1.0ed746b39cbb7614p-2), math.floatEpsAt(f80, -0x1.08c71aa0e5090998p-2));
    try testing.expectApproxEqAbs(0x1.2a24e22d861debfep0, atanExtended80(0x1.299d54ac7d6afc52p1), math.floatEpsAt(f80, 0x1.2a24e22d861debfep0));
    try testing.expectApproxEqAbs(-0x1.1c617825f97512b8p0, atanExtended80(-0x1.0264fb9f3d50e4fp1), math.floatEpsAt(f80, -0x1.1c617825f97512b8p0));
}

test "atanBinary128.special" {
    try testing.expectEqual(0x0p+0, atanBinary128(0x0p+0));
    try testing.expectEqual(-0x0p+0, atanBinary128(-0x0p+0));
    try testing.expectApproxEqAbs(0x1.921fb54442d18469898cc51701b8p-1, atanBinary128(0x1p+0), math.floatEpsAt(f128, 0x1.921fb54442d18469898cc51701b8p-1));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18469898cc51701b8p-1, atanBinary128(-0x1p+0), math.floatEpsAt(f128, -0x1.921fb54442d18469898cc51701b8p-1));
    try testing.expectApproxEqAbs(0x1.921fb54442d18469898cc51701b8p0, atanBinary128(math.inf(f128)), math.floatEpsAt(f128, 0x1.921fb54442d18469898cc51701b8p0));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18469898cc51701b8p0, atanBinary128(-math.inf(f128)), math.floatEpsAt(f128, -0x1.921fb54442d18469898cc51701b8p0));
    try testing.expect(math.isNan(atanBinary128(math.nan(f128))));
}

test "atanBinary128" {
    try testing.expectApproxEqAbs(-0x1.74c61f437701660ff76989d23707p-2, atanBinary128(-0x1.8629d0244cdcbed71792ccdec26dp-2), math.floatEpsAt(f128, -0x1.74c61f437701660ff76989d23707p-2));
    try testing.expectApproxEqAbs(-0x1.375fd7987cc1fd0119cf0cc5b708p0, atanBinary128(-0x1.59d42d4659936d9e22b5dea4faefp1), math.floatEpsAt(f128, -0x1.375fd7987cc1fd0119cf0cc5b708p0));
    try testing.expectApproxEqAbs(-0x1.11b8adeba5615e0370722b511231p0, atanBinary128(-0x1.d2dbe23d04f067b42da3f8efdf57p0), math.floatEpsAt(f128, -0x1.11b8adeba5615e0370722b511231p0));
    try testing.expectApproxEqAbs(-0x1.33d28ca76253964cb5d3581cdd88p-1, atanBinary128(-0x1.5f314e72398e7dbbe70fb072983ep-1), math.floatEpsAt(f128, -0x1.33d28ca76253964cb5d3581cdd88p-1));
    try testing.expectApproxEqAbs(0x1.37082ce2dd03010bbea814dc5882p0, atanBinary128(0x1.5869af37b7d078caa3456c44aecep1), math.floatEpsAt(f128, 0x1.37082ce2dd03010bbea814dc5882p0));
    try testing.expectApproxEqAbs(-0x1.99d7cac66dd4438077284b491a91p-2, atanBinary128(-0x1.b13a05a66261821a364ad8c6c999p-2), math.floatEpsAt(f128, -0x1.99d7cac66dd4438077284b491a91p-2));
    try testing.expectApproxEqAbs(0x1.2fcb120468e8d9ebdb74702314c8p0, atanBinary128(0x1.3cb0f12f39d899c0d963ac413297p1), math.floatEpsAt(f128, 0x1.2fcb120468e8d9ebdb74702314c8p0));
    try testing.expectApproxEqAbs(-0x1.08c71aa0e5090998206fbbe2090fp-2, atanBinary128(-0x1.0ed746b39cbb7614d8735e8315a8p-2), math.floatEpsAt(f128, -0x1.08c71aa0e5090998206fbbe2090fp-2));
    try testing.expectApproxEqAbs(0x1.2a24e22d861debfd6f974500567fp0, atanBinary128(0x1.299d54ac7d6afc5154643b601519p1), math.floatEpsAt(f128, 0x1.2a24e22d861debfd6f974500567fp0));
    try testing.expectApproxEqAbs(-0x1.1c617825f97512b7f38656ab12cdp0, atanBinary128(-0x1.0264fb9f3d50e4f0f966f0686064p1), math.floatEpsAt(f128, -0x1.1c617825f97512b7f38656ab12cdp0));
}

fn atanBinary32Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f32)) @TypeOf(x) {
    const sign_mask: @Vector(vec_len, u32) = @splat(0x80000000);
    const neg_one: @Vector(vec_len, f32) = @splat(-1.0);
    const pi_over_2: @Vector(vec_len, u32) = @splat(0x3fc90fdb);
    const zero: @Vector(vec_len, u32) = @splat(0);
    const c0: @Vector(vec_len, f32) = @splat(-0x1.5554dcp-2);
    const c1: @Vector(vec_len, f32) = @splat(0x1.9978ecp-3);
    const c2: @Vector(vec_len, f32) = @splat(-0x1.230a94p-3);
    const c3: @Vector(vec_len, f32) = @splat(0x1.b4debp-4);
    const c4: @Vector(vec_len, f32) = @splat(-0x1.3550dap-4);
    const c5: @Vector(vec_len, f32) = @splat(0x1.61eebp-5);
    const c6: @Vector(vec_len, f32) = @splat(-0x1.0c17d4p-6);
    const c7: @Vector(vec_len, f32) = @splat(0x1.7ea694p-9);

    const ix: @Vector(vec_len, u32) = @bitCast(x);
    const sign = ix & sign_mask;
    const pred = @abs(x) > @abs(neg_one);
    const z = @select(f32, pred, neg_one / x, x);
    const shift: @Vector(vec_len, f32) = @bitCast(@select(u32, pred, pi_over_2 ^ sign, zero));
    const z2 = z * z;
    const z3 = z * z2;
    const z4 = z2 * z2;
    const z8 = z4 * z4;
    const p0_1 = @mulAdd(@Vector(vec_len, f32), z2, c1, c0);
    const p2_3 = @mulAdd(@Vector(vec_len, f32), z2, c3, c2);
    const p4_5 = @mulAdd(@Vector(vec_len, f32), z2, c5, c4);
    const p6_7 = @mulAdd(@Vector(vec_len, f32), z2, c7, c6);
    const p0_3 = @mulAdd(@Vector(vec_len, f32), z4, p2_3, p0_1);
    const p4_7 = @mulAdd(@Vector(vec_len, f32), z4, p6_7, p4_5);
    const p0_7 = @mulAdd(@Vector(vec_len, f32), z8, p4_7, p0_3);
    return @mulAdd(@Vector(vec_len, f32), z3, p0_7, shift + z);
}

fn atanBinary64Vec(comptime vec_len: comptime_int, x: @Vector(vec_len, f64)) @TypeOf(x) {
    const sign_mask: @Vector(vec_len, u64) = @splat(0x8000000000000000);
    const neg_one: @Vector(vec_len, f64) = @splat(-1.0);
    const pi_over_2: @Vector(vec_len, u64) = @splat(0x3ff921fb54442d18);
    const zero: @Vector(vec_len, u64) = @splat(0);
    const c0: @Vector(vec_len, f64) = @splat(-0x1.555555555552ap-2);
    const c1: @Vector(vec_len, f64) = @splat(0x1.9999999995aebp-3);
    const c2: @Vector(vec_len, f64) = @splat(-0x1.24924923923f6p-3);
    const c3: @Vector(vec_len, f64) = @splat(0x1.c71c7184288a2p-4);
    const c4: @Vector(vec_len, f64) = @splat(-0x1.745d11fb3d32bp-4);
    const c5: @Vector(vec_len, f64) = @splat(0x1.3b136a18051b9p-4);
    const c6: @Vector(vec_len, f64) = @splat(-0x1.110e6d985f496p-4);
    const c7: @Vector(vec_len, f64) = @splat(0x1.e1bcf7f08801dp-5);
    const c8: @Vector(vec_len, f64) = @splat(-0x1.ae644e28058c3p-5);
    const c9: @Vector(vec_len, f64) = @splat(0x1.82eeb1fed85c6p-5);
    const c10: @Vector(vec_len, f64) = @splat(-0x1.59d7f901566cbp-5);
    const c11: @Vector(vec_len, f64) = @splat(0x1.2c982855ab069p-5);
    const c12: @Vector(vec_len, f64) = @splat(-0x1.eb49592998177p-6);
    const c13: @Vector(vec_len, f64) = @splat(0x1.69d8b396e3d38p-6);
    const c14: @Vector(vec_len, f64) = @splat(-0x1.ca980345c4204p-7);
    const c15: @Vector(vec_len, f64) = @splat(0x1.dc050eafde0b3p-8);
    const c16: @Vector(vec_len, f64) = @splat(-0x1.7ea70755b8eccp-9);
    const c17: @Vector(vec_len, f64) = @splat(0x1.ba3da3de903e8p-11);
    const c18: @Vector(vec_len, f64) = @splat(-0x1.44a4b059b6f67p-13);
    const c19: @Vector(vec_len, f64) = @splat(0x1.c4a45029e5a91p-17);

    const ix: @Vector(vec_len, u64) = @bitCast(x);
    const sign = ix & sign_mask;
    const pred = @abs(x) > @abs(neg_one);
    const shift: @Vector(vec_len, f64) = @bitCast(@select(u64, pred, pi_over_2 ^ sign, zero));
    const z = @select(f64, pred, neg_one / x, x);
    const z2 = z * z;
    const z3 = z * z2;
    const z4 = z2 * z2;
    const z8 = z4 * z4;
    const z16 = z8 * z8;
    const p0_1 = @mulAdd(@Vector(vec_len, f64), z2, c1, c0);
    const p2_3 = @mulAdd(@Vector(vec_len, f64), z2, c3, c2);
    const p0_3 = @mulAdd(@Vector(vec_len, f64), z4, p2_3, p0_1);
    const p4_5 = @mulAdd(@Vector(vec_len, f64), z2, c5, c4);
    const p6_7 = @mulAdd(@Vector(vec_len, f64), z2, c7, c6);
    const p4_7 = @mulAdd(@Vector(vec_len, f64), z4, p6_7, p4_5);
    const p0_7 = @mulAdd(@Vector(vec_len, f64), z8, p4_7, p0_3);
    const p8_9 = @mulAdd(@Vector(vec_len, f64), z2, c9, c8);
    const p10_11 = @mulAdd(@Vector(vec_len, f64), z2, c11, c10);
    const p8_11 = @mulAdd(@Vector(vec_len, f64), z4, p10_11, p8_9);
    const p12_13 = @mulAdd(@Vector(vec_len, f64), z2, c13, c12);
    const p14_15 = @mulAdd(@Vector(vec_len, f64), z2, c15, c14);
    const p12_15 = @mulAdd(@Vector(vec_len, f64), z4, p14_15, p12_13);
    const p16_17 = @mulAdd(@Vector(vec_len, f64), z2, c17, c16);
    const p18_19 = @mulAdd(@Vector(vec_len, f64), z2, c19, c18);
    const p16_19 = @mulAdd(@Vector(vec_len, f64), z4, p18_19, p16_17);
    const p8_15 = @mulAdd(@Vector(vec_len, f64), z8, p12_15, p8_11);
    const p8_19 = @mulAdd(@Vector(vec_len, f64), z16, p16_19, p8_15);
    const p0_19 = @mulAdd(@Vector(vec_len, f64), p8_19, z16, p0_7);
    return @mulAdd(@Vector(vec_len, f64), z3, p0_19, shift + z);
}

test "atanBinary32Vec.special" {
    const input: @Vector(7, f32) = .{
        0x0p+0,
        -0x0p+0,
        0x1p+0,
        -0x1p+0,
        math.inf(f32),
        -math.inf(f32),
        math.nan(f32),
    };
    const output = atanBinary32Vec(7, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expectApproxEqAbs(0x1.921fb6p-1, output[2], math.floatEpsAt(f32, 0x1.921fb6p-1));
    try testing.expectApproxEqAbs(-0x1.921fb6p-1, output[3], math.floatEpsAt(f32, -0x1.921fb6p-1));
    try testing.expectApproxEqAbs(0x1.921fb6p+0, output[4], math.floatEpsAt(f32, 0x1.921fb6p+0));
    try testing.expectApproxEqAbs(-0x1.921fb6p+0, output[5], math.floatEpsAt(f32, -0x1.921fb6p+0));
    try testing.expect(math.isNan(output[6]));
}

test "atanBinary32Vec" {
    const input: @Vector(10, f32) = .{
        -0x1.8629dp-2,
        -0x1.59d42ep1,
        -0x1.d2dbe2p0,
        -0x1.5f314ep-1,
        0x1.5869bp1,
        -0x1.b13a06p-2,
        0x1.3cb0f2p1,
        -0x1.0ed746p-2,
        0x1.299d54p1,
        -0x1.0264fcp1,
    };
    const output = atanBinary32Vec(10, input);
    try testing.expectApproxEqAbs(-0x1.74c62p-2, output[0], math.floatEpsAt(f32, -0x1.74c62p-2));
    try testing.expectApproxEqAbs(-0x1.375fd8p0, output[1], math.floatEpsAt(f32, -0x1.375fd8p0));
    try testing.expectApproxEqAbs(-0x1.11b8aep0, output[2], math.floatEpsAt(f32, -0x1.11b8aep0));
    try testing.expectApproxEqAbs(-0x1.33d28cp-1, output[3], math.floatEpsAt(f32, -0x1.33d28cp-1));
    try testing.expectApproxEqAbs(0x1.37082ep0, output[4], math.floatEpsAt(f32, 0x1.37082ep0));
    try testing.expectApproxEqAbs(-0x1.99d7cap-2, output[5], math.floatEpsAt(f32, -0x1.99d7cap-2));
    try testing.expectApproxEqAbs(0x1.2fcb12p0, output[6], math.floatEpsAt(f32, 0x1.2fcb12p0));
    try testing.expectApproxEqAbs(-0x1.08c71ap-2, output[7], math.floatEpsAt(f32, -0x1.08c71ap-2));
    try testing.expectApproxEqAbs(0x1.2a24e2p0, output[8], math.floatEpsAt(f32, 0x1.2a24e2p0));
    try testing.expectApproxEqAbs(-0x1.1c6178p0, output[9], math.floatEpsAt(f32, -0x1.1c6178p0));
}

test "atanBinary64Vec.special" {
    const input: @Vector(7, f64) = .{
        0x0p+0,
        -0x0p+0,
        0x1p+0,
        -0x1p+0,
        math.inf(f64),
        -math.inf(f64),
        math.nan(f64),
    };
    const output = atanBinary64Vec(7, input);
    try testing.expectEqual(0x0p+0, output[0]);
    try testing.expectEqual(-0x0p+0, output[1]);
    try testing.expectApproxEqAbs(0x1.921fb54442d18p-1, output[2], math.floatEpsAt(f64, 0x1.921fb54442d18p-1));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18p-1, output[3], math.floatEpsAt(f64, -0x1.921fb54442d18p-1));
    try testing.expectApproxEqAbs(0x1.921fb54442d18p+0, output[4], math.floatEpsAt(f64, 0x1.921fb54442d18p+0));
    try testing.expectApproxEqAbs(-0x1.921fb54442d18p+0, output[5], math.floatEpsAt(f64, -0x1.921fb54442d18p+0));
    try testing.expect(math.isNan(output[6]));
}

test "atanBinary64Vec" {
    const input: @Vector(10, f64) = .{
        -0x1.8629d0244cdccp-2,
        -0x1.59d42d4659937p1,
        -0x1.d2dbe23d04f06p0,
        -0x1.5f314e72398e8p-1,
        0x1.5869af37b7d08p1,
        -0x1.b13a05a662618p-2,
        0x1.3cb0f12f39d8ap1,
        -0x1.0ed746b39cbb7p-2,
        0x1.299d54ac7d6bp1,
        -0x1.0264fb9f3d50ep1,
    };
    const output = atanBinary64Vec(10, input);
    try testing.expectApproxEqAbs(-0x1.74c61f4377016p-2, output[0], math.floatEpsAt(f64, -0x1.74c61f4377016p-2));
    try testing.expectApproxEqAbs(-0x1.375fd7987cc2p0, output[1], math.floatEpsAt(f64, -0x1.375fd7987cc2p0));
    try testing.expectApproxEqAbs(-0x1.11b8adeba5616p0, output[2], math.floatEpsAt(f64, -0x1.11b8adeba5616p0));
    try testing.expectApproxEqAbs(-0x1.33d28ca762539p-1, output[3], math.floatEpsAt(f64, -0x1.33d28ca762539p-1));
    try testing.expectApproxEqAbs(0x1.37082ce2dd03p0, output[4], math.floatEpsAt(f64, 0x1.37082ce2dd03p0));
    try testing.expectApproxEqAbs(-0x1.99d7cac66dd44p-2, output[5], math.floatEpsAt(f64, -0x1.99d7cac66dd44p-2));
    try testing.expectApproxEqAbs(0x1.2fcb120468e8ep0, output[6], math.floatEpsAt(f64, 0x1.2fcb120468e8ep0));
    try testing.expectApproxEqAbs(-0x1.08c71aa0e509p-2, output[7], math.floatEpsAt(f64, -0x1.08c71aa0e509p-2));
    try testing.expectApproxEqAbs(0x1.2a24e22d861dfp0, output[8], math.floatEpsAt(f64, 0x1.2a24e22d861dfp0));
    try testing.expectApproxEqAbs(-0x1.1c617825f9751p0, output[9], math.floatEpsAt(f64, -0x1.1c617825f9751p0));
}
