const std = @import("std");
const builtin = @import("builtin");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const is_x86_64_linux = builtin.cpu.arch == .x86_64 and builtin.os.tag == .linux;

comptime {
    if (builtin.zig_backend != .stage2_arm and
        !(builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) and // MSVC doesn't support inline assembly
        is_x86_64_linux)
    {
        asm (
            \\.globl this_is_my_alias;
        );
        // test multiple asm per comptime block
        asm (
            \\.type this_is_my_alias, @function;
            \\.set this_is_my_alias, derp;
        );
    } else if (builtin.zig_backend == .stage2_spirv) {
        asm (
            \\%a = OpString "hello there"
        );
    }
}

test "module level assembly" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_x86_64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    if (is_x86_64_linux) {
        try expect(this_is_my_alias() == 1234);
    }
}

test "output constraint modifiers" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    // This is only testing compilation.
    var a: u32 = 3;
    asm volatile (""
        : [_] "=m,r" (a),
        :
        : .{});
    asm volatile (""
        : [_] "=r,m" (a),
        :
        : .{});
}

test "alternative constraints" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch.isLoongArch()) return error.SkipZigTest; // https://github.com/llvm/llvm-project/issues/159200

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    // Make sure we allow commas as a separator for alternative constraints.
    var a: u32 = 3;
    asm volatile (""
        : [_] "=r,m" (a),
        : [_] "r,m" (a),
    );
}

test "sized integer/float in asm input" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    asm volatile (""
        :
        : [_] "m" (@as(usize, 3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(i15, -3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(u3, 3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(i3, 3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(u121, 3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(i121, 3)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(f32, 3.17)),
    );
    asm volatile (""
        :
        : [_] "m" (@as(f64, 3.17)),
    );
}

test "struct/array/union types as input values" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    asm volatile (""
        :
        : [_] "m" (@as([1]u32, undefined)),
    ); // fails
    asm volatile (""
        :
        : [_] "m" (@as(struct { x: u32, y: u8 }, undefined)),
    ); // fails
    asm volatile (""
        :
        : [_] "m" (@as(union { x: u32, y: u8 }, undefined)),
    ); // fails
}

extern fn this_is_my_alias() i32;

export fn derp() i32 {
    return 1234;
}

test "rw constraint (x86_64)" {
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.target.cpu.arch != .x86_64) return error.SkipZigTest;

    var res: i32 = 5;
    asm ("addl %[b], %[a]"
        : [a] "+r" (res),
        : [b] "r" (@as(i32, 13)),
        : .{ .flags = true });
    try expectEqual(@as(i32, 18), res);
}

test "asm modifiers (AArch64)" {
    if (!builtin.target.cpu.arch.isAARCH64()) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    var x: u32 = 15;
    _ = &x;
    const double = asm ("add %[ret:w], %[in:w], %[in:w]"
        : [ret] "=r" (-> u32),
        : [in] "r" (x),
    );
    try expectEqual(2 * x, double);
}

test "packed output types (x86_64)" {
    if (builtin.target.cpu.arch != .x86_64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly

    const S = packed struct(u32) { x: u32 };
    {
        const s: S = asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (-> S),
        );
        try expect(s.x == 123);
    }
    {
        var s: S = undefined;
        asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (s),
        );
        try expect(s.x == 123);
    }

    const U = packed union(u32) { x: u32 };
    {
        const u: U = asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (-> U),
        );
        try expect(u.x == 123);
    }
    {
        var u: U = undefined;
        asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (u),
        );
        try expect(u.x == 123);
    }
}

test "extern output types (x86_64)" {
    if (builtin.target.cpu.arch != .x86_64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest; // MSVC doesn't support inline assembly
    if (builtin.zig_backend == .stage2_llvm) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/31531

    const S = extern struct { x: u32 };
    {
        const s: S = asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (-> S),
        );
        try expect(s.x == 123);
    }
    {
        var s: S = undefined;
        asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (s),
        );
        try expect(s.x == 123);
    }

    const U = extern union { x: u32 };
    {
        const u: U = asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (-> U),
        );
        try expect(u.x == 123);
    }
    {
        var u: U = undefined;
        asm volatile ("mov $123, %[ret]"
            : [ret] "=r" (u),
        );
        try expect(u.x == 123);
    }
}

test "riscv abi register aliases as clobbers" {
    if (!builtin.target.cpu.arch.isRISCV()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.os.tag == .windows) return error.SkipZigTest;

    if (!comptime builtin.cpu.arch.isRISCV()) return error.SkipZigTest;

    // Verify that ABI alias names are accepted as clobbers for RISC-V.
    asm volatile ("" ::: .{ .ra = true, .sp = true, .gp = true, .tp = true });
    asm volatile ("" ::: .{ .a0 = true, .a1 = true, .a2 = true, .a3 = true, .a4 = true, .a5 = true, .a6 = true, .a7 = true });
    asm volatile ("" ::: .{ .t0 = true, .t1 = true, .t2 = true, .t3 = true, .t4 = true, .t5 = true, .t6 = true });
    asm volatile ("" ::: .{ .s0 = true, .fp = true, .s1 = true, .s2 = true, .s3 = true, .s4 = true, .s5 = true, .s6 = true, .s7 = true, .s8 = true, .s9 = true, .s10 = true, .s11 = true });
    asm volatile ("" ::: .{ .fa0 = true, .fa1 = true, .ft0 = true, .fs0 = true });
}
