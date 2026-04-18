const builtin = @import("builtin");
const std = @import("std");

inline fn bit(input: u32, offset: u5) bool {
    return (input >> offset) & 1 != 0;
}

fn setFeature(cpu: *std.Target.Cpu, feature: std.Target.loongarch.Feature, enabled: bool) void {
    const idx = @as(std.Target.Cpu.Feature.Set.Index, @intFromEnum(feature));

    if (enabled) cpu.features.addFeature(idx) else cpu.features.removeFeature(idx);
}

pub fn detectNativeCpuAndFeatures(
    arch: std.Target.Cpu.Arch,
    os: std.Target.Os,
    query: std.Target.Query,
) ?std.Target.Cpu {
    _ = os;
    _ = query;

    var cpu: std.Target.Cpu = .{
        .arch = arch,
        .model = switch (cpucfg(0) & 0xf000) {
            else => return null,
            0xc000 => &std.Target.loongarch.cpu.la464,
            0xd000 => &std.Target.loongarch.cpu.la664,
        },
        .features = .empty,
    };

    cpu.features.addFeatureSet(cpu.model.features);

    const cfg1 = cpucfg(1);
    const cfg2 = cpucfg(2);
    const cfg3 = cpucfg(3);

    setFeature(&cpu, .ual, bit(cfg1, 20));

    const has_fpu = bit(cfg2, 0);
    setFeature(&cpu, .f, has_fpu and bit(cfg2, 1));
    setFeature(&cpu, .d, has_fpu and bit(cfg2, 2));

    setFeature(&cpu, .lsx, bit(cfg2, 6));
    setFeature(&cpu, .lasx, bit(cfg2, 7));
    setFeature(&cpu, .lvz, bit(cfg2, 10));

    setFeature(&cpu, .lbt, bit(cfg2, 18) and bit(cfg2, 19) and bit(cfg2, 20));

    setFeature(&cpu, .frecipe, bit(cfg2, 25));
    setFeature(&cpu, .div32, bit(cfg2, 26));
    setFeature(&cpu, .lam_bh, bit(cfg2, 27));
    setFeature(&cpu, .lamcas, bit(cfg2, 28));
    setFeature(&cpu, .scq, bit(cfg2, 30));

    setFeature(&cpu, .ld_seq_sa, bit(cfg3, 23));

    cpu.features.populateDependencies(cpu.arch.allFeaturesList());

    return cpu;
}

/// This is a workaround for the C backend until zig has the ability to put
/// C code in inline assembly.
extern fn zig_loongarch_cpucfg(word: u32, result: *u32) callconv(.c) void;

fn cpucfg(word: u32) u32 {
    var result: u32 = undefined;

    if (builtin.zig_backend == .stage2_c) {
        zig_loongarch_cpucfg(word, &result);
    } else {
        asm ("cpucfg %[result], %[word]"
            : [result] "=r" (result),
            : [word] "r" (word),
        );
    }

    return result;
}
