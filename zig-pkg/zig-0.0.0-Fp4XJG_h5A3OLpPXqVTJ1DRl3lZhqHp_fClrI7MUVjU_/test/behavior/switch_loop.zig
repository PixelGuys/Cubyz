const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;

test "simple switch loop" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        fn doTheTest() !void {
            var start: u32 = undefined;
            start = 32;
            const result: u32 = s: switch (start) {
                0 => 0,
                1 => 1,
                2 => 2,
                3 => 3,
                else => |x| continue :s x / 2,
            };
            try expect(result == 2);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with ranges" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        fn doTheTest() !void {
            var start: u32 = undefined;
            start = 32;
            const result = s: switch (start) {
                0...3 => |x| x,
                else => |x| continue :s x / 2,
            };
            try expect(result == 2);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop on enum" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        const E = enum { a, b, c };

        fn doTheTest() !void {
            var start: E = undefined;
            start = .a;
            const result: u32 = s: switch (start) {
                .a => continue :s .b,
                .b => continue :s .c,
                .c => 123,
            };
            try expect(result == 123);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with error set" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        const E = error{ Foo, Bar, Baz };

        fn doTheTest() !void {
            var start: E = undefined;
            start = error.Foo;
            const result: u32 = s: switch (start) {
                error.Foo => continue :s error.Bar,
                error.Bar => continue :s error.Baz,
                error.Baz => 123,
            };
            try expect(result == 123);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop on tagged union" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const S = struct {
        const U = union(enum) {
            a: u32,
            b: f32,
            c: f32,
        };

        fn doTheTest() !void {
            var start: U = undefined;
            start = .{ .a = 80 };
            const result = s: switch (start) {
                .a => |x| switch (x) {
                    0...49 => continue :s .{ .b = @floatFromInt(x) },
                    50 => continue :s .{ .c = @floatFromInt(x) },
                    else => continue :s .{ .a = x / 2 },
                },
                .b => |x| x,
                .c => return error.TestFailed,
            };
            try expect(result == 40.0);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop dispatching instructions" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        const Inst = union(enum) {
            set: u32,
            add: u32,
            sub: u32,
            end,
        };

        fn doTheTest() !void {
            var insts: [5]Inst = undefined;
            @memcpy(&insts, &[5]Inst{
                .{ .set = 123 },
                .{ .add = 100 },
                .{ .sub = 50 },
                .{ .sub = 10 },
                .end,
            });
            var i: u32 = 0;
            var cur: u32 = undefined;
            eval: switch (insts[0]) {
                .set => |x| {
                    cur = x;
                    i += 1;
                    continue :eval insts[i];
                },
                .add => |x| {
                    cur += x;
                    i += 1;
                    continue :eval insts[i];
                },
                .sub => |x| {
                    cur -= x;
                    i += 1;
                    continue :eval insts[i];
                },
                .end => {},
            }
            try expect(cur == 163);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with pointer capture" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        const U = union(enum) {
            a: u32,
            b: u32,
            c: u32,
        };

        fn doTheTest() !void {
            var a: U = .{ .a = 100 };
            var b: U = .{ .b = 200 };
            var c: U = .{ .c = 300 };
            inc: switch (a) {
                .a => |*x| {
                    x.* += 1;
                    continue :inc b;
                },
                .b => |*x| {
                    x.* += 10;
                    continue :inc c;
                },
                .c => |*x| {
                    x.* += 50;
                },
            }
            try expect(a.a == 101);
            try expect(b.b == 210);
            try expect(c.c == 350);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "unanalyzed continue with operand" {
    @setRuntimeSafety(false);
    label: switch (false) {
        false => if (false) continue :label true,
        true => {},
    }
}

test "switch loop on larger than pointer integer" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    var entry: @Int(.unsigned, @bitSizeOf(usize) + 1) = undefined;
    entry = 0;
    loop: switch (entry) {
        0 => {
            entry += 1;
            continue :loop 1;
        },
        1 => |x| {
            entry += 1;
            continue :loop x + 1;
        },
        2 => entry += 1,
        else => unreachable,
    }
    try expect(entry == 3);
}

test "switch loop on non-exhaustive enum" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    const S = struct {
        const E = enum(u8) { a, b, c, _ };

        fn doTheTest() !void {
            var start: E = undefined;
            start = .a;
            const result: u32 = s: switch (start) {
                .a => continue :s .c,
                else => continue :s @enumFromInt(123),
                .b, _ => |x| break :s @intFromEnum(x),
            };
            try expect(result == 123);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with discarded tag capture" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        const U = union(enum) {
            a: u32,
            b: u32,
            c: u32,
        };

        fn doTheTest() void {
            const a: U = .{ .a = 10 };
            blk: switch (a) {
                inline .b => |_, tag| {
                    _ = tag;
                    continue :blk .{ .c = 20 };
                },
                else => {},
            }
        }
    };
    S.doTheTest();
    comptime S.doTheTest();
}

test "switch loop with single catch-all prong" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        const E = enum { a, b, c };
        const U = union(E) { a: u32, b: u16, c: u8 };

        fn doTheTest() !void {
            var x: usize = 0;
            label: switch (E.a) {
                else => {
                    x += 1;
                    if (x == 10) break :label;
                    if (x >= 5) continue :label .b;
                    continue :label .c;
                },
            }
            try expect(x == 10);

            label: switch (E.a) {
                .a, .b, .c => {
                    x += 1;
                    if (x == 20) break :label;
                    if (x >= 15) continue :label .b;
                    continue :label .c;
                },
            }
            try expect(x == 20);

            label: switch (E.a) {
                else => if (false) continue :label true,
            }

            const ok = label: switch (U{ .a = 123 }) {
                else => |u| {
                    const y: u32 = switch (u) {
                        inline else => |y| y,
                    };
                    if (y == 456) break :label true;
                    continue :label .{ .b = 456 };
                },
            };
            comptime assert(ok);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop on type with opv" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        const E = enum { opv };
        const U = union(E) { opv: u0 };

        fn doTheTest() !void {
            var x: usize = 0;
            label: switch (E.opv) {
                .opv => {
                    x += 1;
                    if (x == 10) break :label;
                    if (x >= 5) continue :label .opv;
                    continue :label .opv;
                },
            }
            try expect(x == 10);

            label: switch (E.opv) {
                else => {
                    x += 1;
                    if (x == 20) break :label;
                    if (x >= 15) continue :label .opv;
                    continue :label .opv;
                },
            }
            try expect(x == 20);

            label: switch (E.opv) {
                .opv => if (false) continue :label true,
            }

            label: switch (U{ .opv = 0 }) {
                .opv => |val| {
                    x += 1;
                    if (x == 30) break :label;
                    if (x >= 25) continue :label .{ .opv = val };
                    continue :label .{ .opv = 0 };
                },
            }
            try expect(x == 30);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with tag capture" {
    const U = union(enum) {
        a,
        b: i32,
        c: u8,
        d: i32,
        e: noreturn,

        fn doTheTest() !void {
            try doTheSwitch(.a);
            try doTheSwitch(.{ .b = 123 });
            try doTheSwitch(.{ .c = 0xFF });
        }
        fn doTheSwitch(u: @This()) !void {
            const ok1 = label: switch (u) {
                .a => |nothing, tag| {
                    comptime assert(nothing == {});
                    comptime assert(tag == .a);
                    try expect(@intFromEnum(tag) == @intFromEnum(@This().a));
                    continue :label .{ .d = 456 };
                },
                .b, .d => |_, tag| {
                    try expect(tag == .b or tag == .d);
                    continue :label .{ .c = 0x0F };
                },
                .e => |payload, tag| {
                    _ = &payload;
                    _ = &tag;
                    return error.AnalyzedNoreturnProng;
                },
                else => |un, tag| {
                    try expect(tag == .c);
                    try expect(un == .c);
                    if (un.c == 0xFF) continue :label .a;
                    if (un.c == 0x00) break :label false;
                    break :label true;
                },
            };
            try expect(ok1);

            const ok2 = label: switch (u) {
                inline .a, .b, .c => |payload, tag| {
                    if (@TypeOf(payload) == void) {
                        comptime assert(tag == .a);
                        continue :label .{ .b = 456 };
                    }
                    if (@TypeOf(payload) == i32) {
                        comptime assert(tag == .b);
                        continue :label .{ .d = payload };
                    }
                    if (@TypeOf(payload) == u8) {
                        comptime assert(tag == .c);
                        continue :label .{ .d = payload };
                    }
                },
                inline else => |payload, tag| {
                    if (@TypeOf(payload) == i32) comptime assert(tag == .d);
                    comptime assert(tag != .e);
                    if (payload == 0) break :label false;
                    break :label true;
                },
            };
            try expect(ok2);
        }
    };

    try U.doTheTest();
    try comptime U.doTheTest();
}

test "switch loop for error handling" {
    const Error = error{ MyError, MyOtherError };
    const S = struct {
        fn doTheTest() !void {
            try doThePayloadSwitch(123);
            try doTheErrSwitch(error.MyError);
            try doTheErrSwitch(error.MyOtherError);
        }
        fn doThePayloadSwitch(eu: Error!u32) !void {
            const x = eu catch |err| label: switch (err) {
                error.MyError => continue :label error.MyOtherError,
                error.MyOtherError => break :label 0,
            };
            try expect(x == 123);

            const y = if (eu) |payload| label: {
                break :label payload * 2;
            } else |err| label: switch (err) {
                error.MyError => continue :label error.MyOtherError,
                error.MyOtherError => break :label 0,
            };
            try expect(y == 246);
        }
        fn doTheErrSwitch(eu: Error!u32) !void {
            const x = eu catch |err| label: switch (err) {
                error.MyError => continue :label error.MyOtherError,
                error.MyOtherError => break :label 123,
            };
            try expect(x == 123);

            const y = if (eu) |payload| label: {
                break :label payload * 2;
            } else |err| label: switch (err) {
                error.MyError => continue :label error.MyOtherError,
                error.MyOtherError => break :label 123,
            };
            try expect(y == 123);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();
}

test "switch loop with packed structs" {
    const P = packed struct {
        a: u7,
        b: u20,

        fn doTheTest(p: @This()) !void {
            const result = s: switch (p) {
                .{ .a = 5, .b = 10 } => |x| x,
                else => |x| continue :s .{ .a = x.a, .b = x.b + 1 },
            };
            try expect(result == @This(){ .a = 5, .b = 10 });
        }
    };
    try P.doTheTest(.{ .a = 5, .b = 0 });
    try comptime P.doTheTest(.{ .a = 5, .b = 0 });
}

test "switch loop with packed unions" {
    const P = packed union {
        a: u7,
        b: i7,

        fn doTheTest(p: @This()) !void {
            const result = s: switch (p) {
                .{ .a = 10 } => |x| x,
                else => |x| continue :s .{ .b = @intCast(x.a + 1) },
            };
            try expect(result == @This(){ .b = 10 });
        }
    };
    try P.doTheTest(.{ .a = 5 });
    try comptime P.doTheTest(.{ .a = 5 });
}

test "switch loop with packed unions with OPV" {
    const P = packed union {
        a: u0,
        b: i0,

        fn doTheTest(p: @This()) !void {
            var looped = false;
            s: switch (p) {
                .{ .b = 0 } => |x| {
                    comptime assert(x.a == 0);
                    if (looped) break :s;
                    looped = true;
                    continue :s .{ .a = 0 };
                },
            }
        }
    };
    try P.doTheTest(.{ .a = 0 });
    try comptime P.doTheTest(.{ .a = 0 });
}

test "switch loop on large types" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest;

    const S = struct {
        fn doTheTest(a: u128, b: i500) !void {
            label: switch (a) {
                0x0,
                0x3...0xFFFF_FFFF_FFFF_FFFF_FFFF_ABCD,
                0xFFFF_FFFF_FFFF_FFFF_FFFF_EF00,
                => return error.TestFailed,
                0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_0000...0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFF0,
                => |val| {
                    continue :label val + 1;
                },
                else => {},
            }
            label: switch (b) {
                0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_0000...0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_1234,
                => return error.TestFailed,
                0xFFFF_1234,
                0xFFFF_FFFF_FFFF_FFFF_FFFF_0123...0xFFFF_FFFF_FFFF_FFFF_FFFF_4567,
                => |val| {
                    continue :label val + 1;
                },
                else => {},
            }
        }
    };
    try S.doTheTest(0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FF00, 0xFFFF_FFFF_FFFF_FFFF_FFFF_4550);
    try comptime S.doTheTest(0xFFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FFFF_FF00, 0xFFFF_FFFF_FFFF_FFFF_FFFF_4550);
}
