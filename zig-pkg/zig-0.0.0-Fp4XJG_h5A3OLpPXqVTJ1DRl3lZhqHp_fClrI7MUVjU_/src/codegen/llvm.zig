const builtin = @import("builtin");

const FuncGen = @import("llvm/FuncGen.zig");
const buildAllocaInner = FuncGen.buildAllocaInner;
const isByRef = FuncGen.isByRef;
const firstParamSRet = FuncGen.firstParamSRet;
const lowerFnRetTy = FuncGen.lowerFnRetTy;
const iterateParamTypes = FuncGen.iterateParamTypes;
const ccAbiPromoteInt = FuncGen.ccAbiPromoteInt;
const aarch64_c_abi = @import("aarch64/abi.zig");

const std = @import("std");
const Io = std.Io;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.codegen);
const DW = std.dwarf;
const Builder = std.zig.llvm.Builder;

const build_options = @import("build_options");
const bindings = if (build_options.have_llvm)
    @import("llvm/bindings.zig")
else
    @compileError("LLVM unavailable");

const link = @import("../link.zig");
const Compilation = @import("../Compilation.zig");
const Zcu = @import("../Zcu.zig");
const InternPool = @import("../InternPool.zig");
const Package = @import("../Package.zig");
const Air = @import("../Air.zig");
const Value = @import("../Value.zig");
const Type = @import("../Type.zig");
const codegen = @import("../codegen.zig");
const dev = @import("../dev.zig");

const target_util = @import("../target.zig");

pub fn legalizeFeatures(_: *const std.Target) ?*const Air.Legalize.Features {
    return comptime &.initMany(&.{
        .expand_int_from_float_safe,
        .expand_int_from_float_optimized_safe,
    });
}

fn subArchName(target: *const std.Target, comptime family: std.Target.Cpu.Arch.Family, mappings: anytype) ?[]const u8 {
    inline for (mappings) |mapping| {
        if (target.cpu.has(family, mapping[0])) return mapping[1];
    }

    return null;
}

pub fn targetTriple(allocator: Allocator, target: *const std.Target) ![]const u8 {
    var llvm_triple = std.array_list.Managed(u8).init(allocator);
    defer llvm_triple.deinit();

    const llvm_arch = switch (target.cpu.arch) {
        .arm => "arm",
        .armeb => "armeb",
        .aarch64 => if (target.abi == .ilp32) "aarch64_32" else "aarch64",
        .aarch64_be => "aarch64_be",
        .arc => "arc",
        .avr => "avr",
        .bpfel => "bpfel",
        .bpfeb => "bpfeb",
        .csky => "csky",
        .hexagon => "hexagon",
        .loongarch32 => "loongarch32",
        .loongarch64 => "loongarch64",
        .m68k => "m68k",
        // MIPS sub-architectures are a bit irregular, so we handle them manually here.
        .mips => if (target.cpu.has(.mips, .mips32r6)) "mipsisa32r6" else "mips",
        .mipsel => if (target.cpu.has(.mips, .mips32r6)) "mipsisa32r6el" else "mipsel",
        .mips64 => if (target.cpu.has(.mips, .mips64r6)) "mipsisa64r6" else "mips64",
        .mips64el => if (target.cpu.has(.mips, .mips64r6)) "mipsisa64r6el" else "mips64el",
        .msp430 => "msp430",
        .powerpc => "powerpc",
        .powerpcle => "powerpcle",
        .powerpc64 => "powerpc64",
        .powerpc64le => "powerpc64le",
        .amdgcn => "amdgcn",
        .riscv32 => "riscv32",
        .riscv32be => "riscv32be",
        .riscv64 => "riscv64",
        .riscv64be => "riscv64be",
        .sparc => "sparc",
        .sparc64 => "sparc64",
        .s390x => "s390x",
        .thumb => "thumb",
        .thumbeb => "thumbeb",
        .x86 => "i386",
        .x86_64 => "x86_64",
        .xcore => "xcore",
        .xtensa => "xtensa",
        .nvptx => "nvptx",
        .nvptx64 => "nvptx64",
        .spirv32 => switch (target.os.tag) {
            .vulkan, .opengl => "spirv",
            else => "spirv32",
        },
        .spirv64 => "spirv64",
        .lanai => "lanai",
        .wasm32 => "wasm32",
        .wasm64 => "wasm64",
        .ve => "ve",

        .alpha,
        .arceb,
        .hppa,
        .hppa64,
        .kalimba,
        .kvx,
        .microblaze,
        .microblazeel,
        .or1k,
        .propeller,
        .sh,
        .sheb,
        .x86_16,
        .xtensaeb,
        => unreachable, // Gated by hasLlvmSupport().
    };

    try llvm_triple.appendSlice(llvm_arch);

    const llvm_sub_arch: ?[]const u8 = switch (target.cpu.arch) {
        .arm, .armeb, .thumb, .thumbeb => subArchName(target, .arm, .{
            .{ .v4t, "v4t" },
            .{ .v5t, "v5t" },
            .{ .v5te, "v5te" },
            .{ .v5tej, "v5tej" },
            .{ .v6, "v6" },
            .{ .v6k, "v6k" },
            .{ .v6kz, "v6kz" },
            .{ .v6m, "v6m" },
            .{ .v6t2, "v6t2" },
            .{ .v7a, "v7a" },
            .{ .v7em, "v7em" },
            .{ .v7m, "v7m" },
            .{ .v7r, "v7r" },
            .{ .v7ve, "v7ve" },
            .{ .v8a, "v8a" },
            .{ .v8_1a, "v8.1a" },
            .{ .v8_2a, "v8.2a" },
            .{ .v8_3a, "v8.3a" },
            .{ .v8_4a, "v8.4a" },
            .{ .v8_5a, "v8.5a" },
            .{ .v8_6a, "v8.6a" },
            .{ .v8_7a, "v8.7a" },
            .{ .v8_8a, "v8.8a" },
            .{ .v8_9a, "v8.9a" },
            .{ .v8m, "v8m.base" },
            .{ .v8m_main, "v8m.main" },
            .{ .v8_1m_main, "v8.1m.main" },
            .{ .v8r, "v8r" },
            .{ .v9a, "v9a" },
            .{ .v9_1a, "v9.1a" },
            .{ .v9_2a, "v9.2a" },
            .{ .v9_3a, "v9.3a" },
            .{ .v9_4a, "v9.4a" },
            .{ .v9_5a, "v9.5a" },
            .{ .v9_6a, "v9.6a" },
        }),
        .powerpc => subArchName(target, .powerpc, .{
            .{ .spe, "spe" },
        }),
        .spirv32, .spirv64 => subArchName(target, .spirv, .{
            .{ .v1_6, "1.6" },
            .{ .v1_5, "1.5" },
            .{ .v1_4, "1.4" },
            .{ .v1_3, "1.3" },
            .{ .v1_2, "1.2" },
            .{ .v1_1, "1.1" },
        }),
        else => null,
    };

    if (llvm_sub_arch) |sub| try llvm_triple.appendSlice(sub);
    try llvm_triple.append('-');

    try llvm_triple.appendSlice(switch (target.os.tag) {
        .driverkit,
        .ios,
        .maccatalyst,
        .macos,
        .tvos,
        .visionos,
        .watchos,
        => "apple",
        .ps4,
        .ps5,
        => "scei",
        .amdhsa,
        .amdpal,
        => "amd",
        .cuda,
        .nvcl,
        => "nvidia",
        .mesa3d,
        => "mesa",
        else => "unknown",
    });
    try llvm_triple.append('-');

    const llvm_os = switch (target.os.tag) {
        .dragonfly => "dragonfly",
        .freebsd => "freebsd",
        .fuchsia => "fuchsia",
        .linux => "linux",
        .netbsd => "netbsd",
        .openbsd => "openbsd",
        .illumos => "solaris",
        .windows, .uefi => "windows",
        .haiku => "haiku",
        .rtems => "rtems",
        .cuda => "cuda",
        .nvcl => "nvcl",
        .amdhsa => "amdhsa",
        .ps3 => "lv2",
        .ps4 => "ps4",
        .ps5 => "ps5",
        .mesa3d => "mesa3d",
        .amdpal => "amdpal",
        .hermit => "hermit",
        .hurd => "hurd",
        .wasi => "wasi",
        .emscripten => "emscripten",
        .macos => "macosx",
        .ios, .maccatalyst => "ios",
        .tvos => "tvos",
        .watchos => "watchos",
        .driverkit => "driverkit",
        .visionos => "xros",
        .serenity => "serenity",
        .vulkan => "vulkan",
        .managarm => "managarm",

        .@"3ds",
        .contiki,
        .freestanding,
        .opencl, // https://llvm.org/docs/SPIRVUsage.html#target-triples
        .opengl,
        .other,
        .plan9,
        .psp,
        .vita,
        => "unknown",
    };
    try llvm_triple.appendSlice(llvm_os);

    switch (target.os.versionRange()) {
        .none,
        .windows,
        => {},
        .semver => |ver| try llvm_triple.print("{d}.{d}.{d}", .{
            ver.min.major,
            ver.min.minor,
            ver.min.patch,
        }),
        inline .linux, .hurd => |ver| try llvm_triple.print("{d}.{d}.{d}", .{
            ver.range.min.major,
            ver.range.min.minor,
            ver.range.min.patch,
        }),
    }
    try llvm_triple.append('-');

    const llvm_abi = switch (target.abi) {
        .none => if (target.os.tag == .maccatalyst) "macabi" else "unknown",
        .gnu => "gnu",
        .gnuabin32 => "gnuabin32",
        .gnuabi64 => "gnuabi64",
        .gnueabi => "gnueabi",
        .gnueabihf => "gnueabihf",
        .gnuf32 => "gnuf32",
        .gnusf => "gnusf",
        .gnux32 => "gnux32",
        .ilp32 => "unknown",
        .eabi => "eabi",
        .eabihf => "eabihf",
        .android => "android",
        .androideabi => "androideabi",
        .musl => switch (target.os.tag) {
            // For WASI/Emscripten, "musl" refers to the libc, not really the ABI.
            // "unknown" provides better compatibility with LLVM-based tooling for these targets.
            .wasi, .emscripten => "unknown",
            else => "musl",
        },
        .muslabin32 => "muslabin32",
        .muslabi64 => "muslabi64",
        .musleabi => "musleabi",
        .musleabihf => "musleabihf",
        .muslf32 => "muslf32",
        .muslsf => "muslsf",
        .muslx32 => "muslx32",
        .msvc => "msvc",
        .itanium => "itanium",
        .simulator => "simulator",
        .ohos, .ohoseabi => "ohos",
    };
    try llvm_triple.appendSlice(llvm_abi);

    switch (target.os.versionRange()) {
        .none,
        .semver,
        .windows,
        => {},
        inline .hurd, .linux => |ver| if (target.abi.isGnu()) {
            try llvm_triple.print("{d}.{d}.{d}", .{
                ver.glibc.major,
                ver.glibc.minor,
                ver.glibc.patch,
            });
        } else if (@TypeOf(ver) == std.Target.Os.LinuxVersionRange and target.abi.isAndroid()) {
            try llvm_triple.print("{d}", .{ver.android});
        },
    }

    return llvm_triple.toOwnedSlice();
}

pub fn supportsTailCall(target: *const std.Target) bool {
    return switch (target.cpu.arch) {
        .wasm32, .wasm64 => target.cpu.has(.wasm, .tail_call),
        // Although these ISAs support tail calls, LLVM does not support tail calls on them.
        .mips, .mipsel, .mips64, .mips64el => false,
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => false,
        else => true,
    };
}

pub fn dataLayout(target: *const std.Target) []const u8 {
    // These data layouts should match Clang.
    return switch (target.cpu.arch) {
        .arc => "e-m:e-p:32:32-i1:8:32-i8:8:32-i16:16:32-i32:32:32-f32:32:32-i64:32-f64:32-a:0:32-n32",
        .xcore => "e-m:e-p:32:32-i1:8:32-i8:8:32-i16:16:32-i64:32-f64:32-a:0:32-n32",
        .hexagon => "e-m:e-p:32:32:32-a:0-n16:32-i64:64:64-i32:32:32-i16:16:16-i1:8:8-f32:32:32-f64:64:64-v32:32:32-v64:64:64-v512:512:512-v1024:1024:1024-v2048:2048:2048",
        .lanai => "E-m:e-p:32:32-i64:64-a:0:32-n32-S64",
        .aarch64 => if (target.ofmt == .macho)
            if (target.os.tag == .windows or target.os.tag == .uefi)
                "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
            else if (target.abi == .ilp32)
                "e-m:o-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
            else
                "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-n32:64-S128-Fn32"
        else if (target.os.tag == .windows or target.os.tag == .uefi)
            "e-m:w-p270:32:32-p271:32:32-p272:64:64-p:64:64-i32:32-i64:64-i128:128-n32:64-S128-Fn32"
        else
            "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32",
        .aarch64_be => "E-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128-Fn32",
        .arm => if (target.ofmt == .macho)
            "e-m:o-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        else
            "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64",
        .armeb, .thumbeb => if (target.ofmt == .macho)
            "E-m:o-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        else
            "E-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64",
        .thumb => if (target.ofmt == .macho)
            "e-m:o-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        else if (target.os.tag == .windows or target.os.tag == .uefi)
            "e-m:w-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64"
        else
            "e-m:e-p:32:32-Fi8-i64:64-v128:64:128-a:0:32-n32-S64",
        .avr => "e-P1-p:16:8-i8:8-i16:8-i32:8-i64:8-f32:8-f64:8-n8-a:8",
        .bpfeb => "E-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
        .bpfel => "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
        .msp430 => "e-m:e-p:16:16-i32:16-i64:16-f32:16-f64:16-a:8-n8:16-S16",
        .mips => "E-m:m-p:32:32-i8:8:32-i16:16:32-i64:64-n32-S64",
        .mipsel => "e-m:m-p:32:32-i8:8:32-i16:16:32-i64:64-n32-S64",
        .mips64 => switch (target.abi) {
            .gnuabin32, .muslabin32 => "E-m:e-p:32:32-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128",
            else => "E-m:e-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128",
        },
        .mips64el => switch (target.abi) {
            .gnuabin32, .muslabin32 => "e-m:e-p:32:32-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128",
            else => "e-m:e-i8:8:32-i16:16:32-i64:64-i128:128-n32:64-S128",
        },
        .m68k => "E-m:e-p:32:16:32-i8:8:8-i16:16:16-i32:16:32-n8:16:32-a:0:16-S16",
        .powerpc => "E-m:e-p:32:32-Fn32-i64:64-n32",
        .powerpcle => "e-m:e-p:32:32-Fn32-i64:64-n32",
        .powerpc64 => switch (target.os.tag) {
            .linux => if (target.abi.isMusl())
                "E-m:e-Fn32-i64:64-i128:128-n32:64-S128-v256:256:256-v512:512:512"
            else
                "E-m:e-Fi64-i64:64-i128:128-n32:64-S128-v256:256:256-v512:512:512",
            .ps3 => "E-m:e-p:32:32-Fi64-i64:64-i128:128-n32:64",
            else => if (target.os.tag == .openbsd or
                (target.os.tag == .freebsd and target.os.version_range.semver.isAtLeast(.{ .major = 13, .minor = 0, .patch = 0 }) orelse false))
                "E-m:e-Fn32-i64:64-i128:128-n32:64"
            else
                "E-m:e-Fi64-i64:64-i128:128-n32:64",
        },
        .powerpc64le => if (target.os.tag == .linux)
            "e-m:e-Fn32-i64:64-i128:128-n32:64-S128-v256:256:256-v512:512:512"
        else
            "e-m:e-Fn32-i64:64-i128:128-n32:64",
        .nvptx => "e-p:32:32-p6:32:32-p7:32:32-i64:64-i128:128-v16:16-v32:32-n16:32:64",
        .nvptx64 => "e-p6:32:32-i64:64-i128:128-v16:16-v32:32-n16:32:64",
        .amdgcn => "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-p7:160:256:256:32-p8:128:128:128:48-p9:192:256:256:32-i64:64-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-n32:64-S32-A5-G1-ni:7:8:9",
        .riscv32 => if (target.cpu.has(.riscv, .e))
            "e-m:e-p:32:32-i64:64-n32-S32"
        else
            "e-m:e-p:32:32-i64:64-n32-S128",
        .riscv32be => if (target.cpu.has(.riscv, .e))
            "E-m:e-p:32:32-i64:64-n32-S32"
        else
            "E-m:e-p:32:32-i64:64-n32-S128",
        .riscv64 => if (target.cpu.has(.riscv, .e))
            "e-m:e-p:64:64-i64:64-i128:128-n32:64-S64"
        else
            "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
        .riscv64be => if (target.cpu.has(.riscv, .e))
            "E-m:e-p:64:64-i64:64-i128:128-n32:64-S64"
        else
            "E-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
        .sparc => "E-m:e-p:32:32-i64:64-i128:128-f128:64-n32-S64",
        .sparc64 => "E-m:e-i64:64-i128:128-n32:64-S128",
        .s390x => "E-m:e-i1:8:16-i8:8:16-i64:64-f128:64-v128:64-a:8:16-n32:64",
        .x86 => if (target.os.tag == .windows or target.os.tag == .uefi) switch (target.abi) {
            .gnu => if (target.ofmt == .coff)
                "e-m:x-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:32-n8:16:32-a:0:32-S32"
            else
                "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:32-n8:16:32-a:0:32-S32",
            else => blk: {
                const msvc = switch (target.abi) {
                    .none, .msvc => true,
                    else => false,
                };

                break :blk if (target.ofmt == .coff)
                    if (msvc)
                        "e-m:x-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32-a:0:32-S32"
                    else
                        "e-m:x-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:32-n8:16:32-a:0:32-S32"
                else if (msvc)
                    "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32-a:0:32-S32"
                else
                    "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:32-n8:16:32-a:0:32-S32";
            },
        } else if (target.ofmt == .macho)
            "e-m:o-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128"
        else
            "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i128:128-f64:32:64-f80:32-n8:16:32-S128",
        .x86_64 => if (target.os.tag.isDarwin() or target.ofmt == .macho)
            "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
        else switch (target.abi) {
            .gnux32, .muslx32 => "e-m:e-p:32:32-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128",
            else => if ((target.os.tag == .windows or target.os.tag == .uefi) and target.ofmt == .coff)
                "e-m:w-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
            else
                "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128",
        },
        .spirv32 => switch (target.os.tag) {
            .vulkan, .opengl => "e-i64:64-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-G1",
            else => "e-p:32:32-i64:64-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-G1",
        },
        .spirv64 => "e-i64:64-v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-G1",
        .wasm32 => if (target.os.tag == .emscripten)
            "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-f128:64-n32:64-S128-ni:1:10:20"
        else
            "e-m:e-p:32:32-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20",
        .wasm64 => if (target.os.tag == .emscripten)
            "e-m:e-p:64:64-p10:8:8-p20:8:8-i64:64-i128:128-f128:64-n32:64-S128-ni:1:10:20"
        else
            "e-m:e-p:64:64-p10:8:8-p20:8:8-i64:64-i128:128-n32:64-S128-ni:1:10:20",
        .ve => "e-m:e-i64:64-n32:64-S128-v64:64:64-v128:64:64-v256:64:64-v512:64:64-v1024:64:64-v2048:64:64-v4096:64:64-v8192:64:64-v16384:64:64",
        .csky => "e-m:e-S32-p:32:32-i32:32:32-i64:32:32-f32:32:32-f64:32:32-v64:32:32-v128:32:32-a:0:32-Fi32-n32",
        .loongarch32 => "e-m:e-p:32:32-i64:64-n32-S128",
        .loongarch64 => "e-m:e-p:64:64-i64:64-i128:128-n32:64-S128",
        .xtensa => "e-m:e-p:32:32-i8:8:32-i16:16:32-i64:64-n32",

        .alpha,
        .arceb,
        .hppa,
        .hppa64,
        .kalimba,
        .kvx,
        .microblaze,
        .microblazeel,
        .or1k,
        .propeller,
        .sh,
        .sheb,
        .x86_16,
        .xtensaeb,
        => unreachable, // Gated by hasLlvmSupport().
    };
}

// Avoid depending on `bindings.CodeModel` in the bitcode-only case.
const CodeModel = enum {
    default,
    tiny,
    small,
    kernel,
    medium,
    large,
};

fn codeModel(model: std.builtin.CodeModel, target: *const std.Target) CodeModel {
    // Roughly match Clang's mapping of GCC code models to LLVM code models.
    return switch (model) {
        .default => .default,
        .extreme, .large => .large,
        .kernel => .kernel,
        .medany => if (target.cpu.arch.isRISCV()) .medium else .large,
        .medium => .medium,
        .medmid => .medium,
        .normal, .medlow, .small => .small,
        .tiny => .tiny,
    };
}

pub const Object = struct {
    gpa: Allocator,
    builder: Builder,

    /// This pool contains only types (and not `@as(type, undefined)`). It has two purposes:
    ///
    /// * Lazily tracking ABI alignment of types, so that `@"align"` attributes can be set to a
    ///   type's ABI alignment before that type is fully resolved. Each type in the pool has a
    ///   corresponding entry in `lazy_abi_aligns`.
    ///
    /// * If `!Object.builder.strip`, lazily tracking debug information types, so that debug
    ///   information can handle indirect self-reference (and so that debug information works
    ///   correctly across incremental updates). Each type has a corresponding entry in
    ///   `debug_types`, provided that `Object.builder.strip` is `false`.
    type_pool: link.ConstPool,

    /// Keyed on `link.ConstPool.Index`.
    lazy_abi_aligns: std.ArrayList(Builder.Alignment.Lazy),

    debug_compile_unit: Builder.Metadata.Optional,

    debug_enums_fwd_ref: Builder.Metadata.Optional,
    debug_globals_fwd_ref: Builder.Metadata.Optional,

    debug_enums: std.ArrayList(Builder.Metadata),
    debug_globals: std.ArrayList(Builder.Metadata),

    debug_file_map: std.AutoHashMapUnmanaged(Zcu.File.Index, Builder.Metadata),

    /// Keyed on `link.ConstPool.Index`.
    debug_types: std.ArrayList(Builder.Metadata),
    /// Initially `.none`, set if the type `anyerror` is lowered to a debug type. The type will not
    /// actually be created until `emit`, which must resolve this reference with an appropriate enum
    /// type from the global error set.
    debug_anyerror_fwd_ref: Builder.Metadata.Optional,

    zcu: *Zcu,
    /// Maps a `Nav` to the corresponding LLVM global.
    nav_map: std.AutoHashMapUnmanaged(InternPool.Nav.Index, Builder.Global.Index),
    /// Same as `nav_map` but for UAVs (which are always global constants).
    uav_map: std.AutoHashMapUnmanaged(struct {
        val: InternPool.Index,
        @"addrspace": std.builtin.AddressSpace,
    }, Builder.Variable.Index),
    /// Maps enum types to their corresponding LLVM functions for implementing the `tag_name` instruction.
    enum_tag_name_map: std.AutoHashMapUnmanaged(InternPool.Index, Builder.Function.Index),
    /// Serves the same purpose as `enum_tag_name_map` but for the `is_named_enum_value` instruction.
    named_enum_map: std.AutoHashMapUnmanaged(InternPool.Index, Builder.Function.Index),
    /// Maps Zig types to LLVM types. The table memory is backed by the GPA of
    /// the compiler.
    /// TODO when InternPool garbage collection is implemented, this map needs
    /// to be garbage collected as well.
    type_map: TypeMap,
    /// The LLVM global table which holds the names corresponding to Zig errors.
    /// Note that the values are not added until `emit`, when all errors in
    /// the compilation are known.
    error_name_table: Builder.Variable.Index,
    /// Constant variable whose value is the number of errors in the Zcu.
    ///
    /// Initially `.none`---populated lazily by `getErrorsLen`.
    ///
    /// If this is not `.none`, the variable's initializer is set in `emit`.
    errors_len_variable: Builder.Variable.Index,

    /// Values for `@llvm.used`.
    used: std.ArrayList(Builder.Constant),

    pub const Ptr = if (dev.env.supports(.llvm_backend)) *Object else noreturn;

    const TypeMap = std.AutoHashMapUnmanaged(InternPool.Index, Builder.Type);

    pub fn create(arena: Allocator, zcu: *Zcu) !Ptr {
        dev.check(.llvm_backend);
        const comp = zcu.comp;
        const gpa = comp.gpa;
        const target = zcu.getTarget();
        const llvm_target_triple = try targetTriple(arena, target);

        var builder = try Builder.init(.{
            .allocator = gpa,
            .strip = comp.config.debug_format == .strip,
            .name = comp.root_name,
            .target = target,
            .triple = llvm_target_triple,
        });
        errdefer builder.deinit();

        builder.data_layout = try builder.string(dataLayout(target));

        const debug_compile_unit, const debug_enums_fwd_ref, const debug_globals_fwd_ref =
            if (!builder.strip) debug_info: {
                // We fully resolve all paths at this point to avoid lack of
                // source line info in stack traces or lack of debugging
                // information which, if relative paths were used, would be
                // very location dependent.
                // TODO: the only concern I have with this is WASI as either host or target, should
                // we leave the paths as relative then?
                // TODO: This is totally wrong. In dwarf, paths are encoded as relative to
                // a particular directory, and then the directory path is specified elsewhere.
                // In the compiler frontend we have it stored correctly in this
                // way already, but here we throw all that sweet information
                // into the garbage can by converting into absolute paths. What
                // a terrible tragedy.
                const compile_unit_dir = try zcu.main_mod.root.toAbsolute(comp.dirs, arena);

                const debug_file = try builder.debugFile(
                    try builder.metadataString(comp.root_name),
                    try builder.metadataString(compile_unit_dir),
                );

                const debug_enums_fwd_ref = try builder.debugForwardReference();
                const debug_globals_fwd_ref = try builder.debugForwardReference();

                const debug_compile_unit = try builder.debugCompileUnit(
                    debug_file,
                    // Don't use the version string here; LLVM misparses it when it
                    // includes the git revision.
                    try builder.metadataStringFmt("zig {d}.{d}.{d}", .{
                        build_options.semver.major,
                        build_options.semver.minor,
                        build_options.semver.patch,
                    }),
                    debug_enums_fwd_ref,
                    debug_globals_fwd_ref,
                    .{ .optimized = comp.root_mod.optimize_mode != .Debug },
                );

                try builder.addNamedMetadata(try builder.string("llvm.dbg.cu"), &.{debug_compile_unit});
                break :debug_info .{
                    debug_compile_unit.toOptional(),
                    debug_enums_fwd_ref.toOptional(),
                    debug_globals_fwd_ref.toOptional(),
                };
            } else .{Builder.Metadata.Optional.none} ** 3;

        const obj = try arena.create(Object);
        obj.* = .{
            .gpa = gpa,
            .builder = builder,
            .type_pool = .empty,
            .lazy_abi_aligns = .empty,
            .debug_compile_unit = debug_compile_unit,
            .debug_enums_fwd_ref = debug_enums_fwd_ref,
            .debug_globals_fwd_ref = debug_globals_fwd_ref,
            .debug_enums = .empty,
            .debug_globals = .empty,
            .debug_file_map = .empty,
            .debug_types = .empty,
            .debug_anyerror_fwd_ref = .none,
            .zcu = zcu,
            .nav_map = .empty,
            .uav_map = .empty,
            .enum_tag_name_map = .empty,
            .named_enum_map = .empty,
            .type_map = .empty,
            .error_name_table = .none,
            .errors_len_variable = .none,
            .used = .empty,
        };
        return obj;
    }

    pub fn deinit(self: *Object) void {
        const gpa = self.gpa;
        self.type_pool.deinit(gpa);
        self.lazy_abi_aligns.deinit(gpa);
        self.debug_enums.deinit(gpa);
        self.debug_globals.deinit(gpa);
        self.debug_file_map.deinit(gpa);
        self.debug_types.deinit(gpa);
        self.nav_map.deinit(gpa);
        self.uav_map.deinit(gpa);
        self.enum_tag_name_map.deinit(gpa);
        self.named_enum_map.deinit(gpa);
        self.type_map.deinit(gpa);
        self.builder.deinit();
        self.* = undefined;
    }

    fn genErrorNameTable(o: *Object) Allocator.Error!void {
        // If o.error_name_table is null, then it was not referenced by any instructions.
        if (o.error_name_table == .none) return;

        const zcu = o.zcu;
        const ip = &zcu.intern_pool;

        const error_name_list = ip.global_error_set.getNamesFromMainThread();
        const llvm_errors = try zcu.gpa.alloc(Builder.Constant, 1 + error_name_list.len);
        defer zcu.gpa.free(llvm_errors);

        // TODO: Address space
        const slice_ty = Type.slice_const_u8_sentinel_0;
        const llvm_usize_ty = try o.lowerType(.usize);
        const llvm_slice_ty = try o.lowerType(slice_ty);
        const llvm_table_ty = try o.builder.arrayType(1 + error_name_list.len, llvm_slice_ty);

        llvm_errors[0] = try o.builder.undefConst(llvm_slice_ty);
        for (llvm_errors[1..], error_name_list) |*llvm_error, name| {
            const name_string = try o.builder.stringNull(name.toSlice(ip));
            const name_init = try o.builder.stringConst(name_string);
            const name_variable_index = try o.builder.addVariable(.empty, name_init.typeOf(&o.builder), .default);
            try name_variable_index.setInitializer(name_init, &o.builder);
            name_variable_index.setMutability(.constant, &o.builder);
            name_variable_index.setAlignment(comptime .fromByteUnits(1), &o.builder);
            const global_index = name_variable_index.ptrConst(&o.builder).global;
            global_index.setLinkage(.private, &o.builder);
            global_index.setUnnamedAddr(.unnamed_addr, &o.builder);

            llvm_error.* = try o.builder.structConst(llvm_slice_ty, &.{
                name_variable_index.toConst(&o.builder),
                try o.builder.intConst(llvm_usize_ty, name_string.slice(&o.builder).?.len - 1),
            });
        }

        try o.error_name_table.setInitializer(
            try o.builder.arrayConst(llvm_table_ty, llvm_errors),
            &o.builder,
        );
    }

    fn genModuleLevelAssembly(object: *Object) Allocator.Error!void {
        const b = &object.builder;
        const gpa = b.gpa;
        b.module_asm.clearRetainingCapacity();
        for (object.zcu.global_assembly.values()) |assembly| {
            try b.module_asm.ensureUnusedCapacity(gpa, assembly.len + 1);
            b.module_asm.appendSliceAssumeCapacity(assembly);
            b.module_asm.appendAssumeCapacity('\n');
        }
        if (b.module_asm.getLastOrNull()) |last| {
            if (last != '\n') try b.module_asm.append(gpa, '\n');
        }
    }

    pub const EmitOptions = struct {
        pre_ir_path: ?[]const u8,
        pre_bc_path: ?[]const u8,
        bin_path: ?[:0]const u8,
        asm_path: ?[:0]const u8,
        post_ir_path: ?[:0]const u8,
        post_bc_path: ?[]const u8,

        is_debug: bool,
        is_small: bool,
        time_report: ?*Compilation.TimeReport,
        sanitize_thread: bool,
        fuzz: bool,
        lto: std.zig.LtoMode,
    };

    pub fn emit(o: *Object, pt: Zcu.PerThread, options: EmitOptions) error{ LinkFailure, OutOfMemory }!void {
        const zcu = o.zcu;
        const comp = zcu.comp;
        const io = comp.io;
        const diags = &comp.link_diags;

        {
            if (o.errors_len_variable != .none) {
                const errors_len = zcu.intern_pool.global_error_set.getNamesFromMainThread().len;
                const init_val = try o.builder.intConst(try o.errorIntType(), errors_len);
                try o.errors_len_variable.setInitializer(init_val, &o.builder);
            }
            try o.genErrorNameTable();
            try o.genModuleLevelAssembly();

            if (o.used.items.len > 0) {
                const array_llvm_ty = try o.builder.arrayType(o.used.items.len, .ptr);
                const init_val = try o.builder.arrayConst(array_llvm_ty, o.used.items);
                const compiler_used_variable = try o.builder.addVariable(
                    try o.builder.strtabString("llvm.used"),
                    array_llvm_ty,
                    .default,
                );
                try compiler_used_variable.setInitializer(init_val, &o.builder);
                compiler_used_variable.setSection(try o.builder.string("llvm.metadata"), &o.builder);
                compiler_used_variable.ptrConst(&o.builder).global.setLinkage(.appending, &o.builder);
            }

            if (!o.builder.strip) {
                if (o.debug_anyerror_fwd_ref.unwrap()) |fwd_ref| {
                    const debug_anyerror_type = try o.lowerDebugAnyerrorType();
                    o.builder.resolveDebugForwardReference(fwd_ref, debug_anyerror_type);
                }

                try o.flushTypePool(pt);

                o.builder.resolveDebugForwardReference(
                    o.debug_enums_fwd_ref.unwrap().?,
                    try o.builder.metadataTuple(o.debug_enums.items),
                );

                o.builder.resolveDebugForwardReference(
                    o.debug_globals_fwd_ref.unwrap().?,
                    try o.builder.metadataTuple(o.debug_globals.items),
                );
            }
        }

        {
            var module_flags = try std.array_list.Managed(Builder.Metadata).initCapacity(o.gpa, 8);
            defer module_flags.deinit();

            const behavior_error = try o.builder.metadataConstant(try o.builder.intConst(.i32, 1));
            const behavior_warning = try o.builder.metadataConstant(try o.builder.intConst(.i32, 2));
            const behavior_max = try o.builder.metadataConstant(try o.builder.intConst(.i32, 7));
            const behavior_min = try o.builder.metadataConstant(try o.builder.intConst(.i32, 8));

            if (target_util.llvmMachineAbi(&comp.root_mod.resolved_target.result)) |abi| {
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_error,
                    (try o.builder.metadataString("target-abi")).toMetadata(),
                    (try o.builder.metadataString(abi)).toMetadata(),
                }));
            }

            const pic_level = target_util.picLevel(&comp.root_mod.resolved_target.result);
            if (comp.root_mod.pic) {
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_min,
                    (try o.builder.metadataString("PIC Level")).toMetadata(),
                    try o.builder.metadataConstant(try o.builder.intConst(.i32, pic_level)),
                }));
            }

            if (comp.config.pie) {
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_max,
                    (try o.builder.metadataString("PIE Level")).toMetadata(),
                    try o.builder.metadataConstant(try o.builder.intConst(.i32, pic_level)),
                }));
            }

            if (comp.root_mod.code_model != .default) {
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_error,
                    (try o.builder.metadataString("Code Model")).toMetadata(),
                    try o.builder.metadataConstant(try o.builder.intConst(.i32, @as(
                        i32,
                        switch (codeModel(comp.root_mod.code_model, &comp.root_mod.resolved_target.result)) {
                            .default => unreachable,
                            .tiny => 0,
                            .small => 1,
                            .kernel => 2,
                            .medium => 3,
                            .large => 4,
                        },
                    ))),
                }));
            }

            if (!o.builder.strip) {
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_warning,
                    (try o.builder.metadataString("Debug Info Version")).toMetadata(),
                    try o.builder.metadataConstant(try o.builder.intConst(.i32, 3)),
                }));

                switch (comp.config.debug_format) {
                    .strip => unreachable,
                    .dwarf => |f| {
                        module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                            behavior_max,
                            (try o.builder.metadataString("Dwarf Version")).toMetadata(),
                            try o.builder.metadataConstant(try o.builder.intConst(.i32, 4)),
                        }));

                        if (f == .@"64") {
                            module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                                behavior_max,
                                (try o.builder.metadataString("DWARF64")).toMetadata(),
                                try o.builder.metadataConstant(.@"1"),
                            }));
                        }
                    },
                    .code_view => {
                        module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                            behavior_warning,
                            (try o.builder.metadataString("CodeView")).toMetadata(),
                            try o.builder.metadataConstant(.@"1"),
                        }));
                    },
                }
            }

            const target = &comp.root_mod.resolved_target.result;
            if (target.os.tag == .windows and (target.cpu.arch == .x86_64 or target.cpu.arch == .x86)) {
                // Add the "RegCallv4" flag so that any functions using `x86_regcallcc` use regcall
                // v4, which is essentially a requirement on Windows. See corresponding logic in
                // `toLlvmCallConvTag`.
                module_flags.appendAssumeCapacity(try o.builder.metadataTuple(&.{
                    behavior_max,
                    (try o.builder.metadataString("RegCallv4")).toMetadata(),
                    try o.builder.metadataConstant(.@"1"),
                }));
            }

            try o.builder.addNamedMetadata(try o.builder.string("llvm.module.flags"), module_flags.items);
        }

        const target_triple_sentinel =
            try o.gpa.dupeZ(u8, o.builder.target_triple.slice(&o.builder).?);
        defer o.gpa.free(target_triple_sentinel);

        const emit_asm_msg = options.asm_path orelse "(none)";
        const emit_bin_msg = options.bin_path orelse "(none)";
        const post_llvm_ir_msg = options.post_ir_path orelse "(none)";
        const post_llvm_bc_msg = options.post_bc_path orelse "(none)";
        log.debug("emit LLVM object asm={s} bin={s} ir={s} bc={s}", .{
            emit_asm_msg, emit_bin_msg, post_llvm_ir_msg, post_llvm_bc_msg,
        });

        const context, const module = emit: {
            if (options.pre_ir_path) |path| {
                if (std.mem.eql(u8, path, "-")) {
                    o.builder.dump(io);
                } else {
                    o.builder.printToFilePath(io, Io.Dir.cwd(), path) catch |err| {
                        log.err("failed printing LLVM module to \"{s}\": {t}", .{ path, err });
                    };
                }
            }

            const bitcode = try o.builder.toBitcode(o.gpa, .{
                .name = "zig",
                .version = build_options.semver,
            });
            defer o.gpa.free(bitcode);

            if (options.pre_bc_path) |path| {
                var file = Io.Dir.cwd().createFile(io, path, .{}) catch |err|
                    return diags.fail("failed to create '{s}': {t}", .{ path, err });
                defer file.close(io);

                const ptr: [*]const u8 = @ptrCast(bitcode.ptr);
                file.writeStreamingAll(io, ptr[0..(bitcode.len * 4)]) catch |err|
                    return diags.fail("failed to write to '{s}': {t}", .{ path, err });
            }

            if (options.asm_path == null and options.bin_path == null and
                options.post_ir_path == null and options.post_bc_path == null) return;

            if (options.post_bc_path) |path| {
                var file = Io.Dir.cwd().createFile(io, path, .{}) catch |err|
                    return diags.fail("failed to create '{s}': {t}", .{ path, err });
                defer file.close(io);

                const ptr: [*]const u8 = @ptrCast(bitcode.ptr);
                file.writeStreamingAll(io, ptr[0..(bitcode.len * 4)]) catch |err|
                    return diags.fail("failed to write to '{s}': {t}", .{ path, err });
            }

            if (!build_options.have_llvm or !comp.config.use_lib_llvm) {
                return diags.fail("emitting without libllvm not implemented", .{});
            }

            initializeLLVMTarget(comp.root_mod.resolved_target.result.cpu.arch);

            const context: *bindings.Context = .create();
            errdefer context.dispose();

            const bitcode_memory_buffer = bindings.MemoryBuffer.createMemoryBufferWithMemoryRange(
                @ptrCast(bitcode.ptr),
                bitcode.len * 4,
                "BitcodeBuffer",
                bindings.Bool.False,
            );
            defer bitcode_memory_buffer.dispose();

            context.enableBrokenDebugInfoCheck();

            var module: *bindings.Module = undefined;
            if (context.parseBitcodeInContext2(bitcode_memory_buffer, &module).toBool() or context.getBrokenDebugInfo()) {
                return diags.fail("Failed to parse bitcode", .{});
            }
            break :emit .{ context, module };
        };
        defer context.dispose();

        var target: *bindings.Target = undefined;
        var error_message: [*:0]const u8 = undefined;
        if (bindings.Target.getFromTriple(target_triple_sentinel, &target, &error_message).toBool()) {
            defer bindings.disposeMessage(error_message);
            return diags.fail("LLVM failed to parse '{s}': {s}", .{ target_triple_sentinel, error_message });
        }

        const optimize_mode = comp.root_mod.optimize_mode;

        const opt_level: bindings.CodeGenOptLevel = if (optimize_mode == .Debug)
            .None
        else
            .Aggressive;

        const reloc_mode: bindings.RelocMode = if (comp.root_mod.pic)
            .PIC
        else if (comp.config.link_mode == .dynamic)
            bindings.RelocMode.DynamicNoPIC
        else
            .Static;

        const code_model: bindings.CodeModel = switch (codeModel(comp.root_mod.code_model, &comp.root_mod.resolved_target.result)) {
            .default => .Default,
            .tiny => .Tiny,
            .small => .Small,
            .kernel => .Kernel,
            .medium => .Medium,
            .large => .Large,
        };

        const float_abi: bindings.TargetMachine.FloatABI = if (comp.root_mod.resolved_target.result.abi.float() == .hard)
            .Hard
        else
            .Soft;

        var target_machine = bindings.TargetMachine.create(
            target,
            target_triple_sentinel,
            if (comp.root_mod.resolved_target.result.cpu.model.llvm_name) |s| s.ptr else null,
            comp.root_mod.resolved_target.llvm_cpu_features.?,
            opt_level,
            reloc_mode,
            code_model,
            comp.function_sections,
            comp.data_sections,
            float_abi,
            if (target_util.llvmMachineAbi(&comp.root_mod.resolved_target.result)) |s| s.ptr else null,
            target_util.useEmulatedTls(&comp.root_mod.resolved_target.result),
        );
        errdefer target_machine.dispose();

        if (comp.llvm_opt_bisect_limit >= 0) {
            context.setOptBisectLimit(comp.llvm_opt_bisect_limit);
        }

        // Unfortunately, LLVM shits the bed when we ask for both binary and assembly.
        // So we call the entire pipeline multiple times if this is requested.
        // var error_message: [*:0]const u8 = undefined;
        var lowered_options: bindings.TargetMachine.EmitOptions = .{
            .is_debug = options.is_debug,
            .is_small = options.is_small,
            .time_report_out = null, // set below to make sure it's only set for a single `emitToFile`
            .tsan = options.sanitize_thread,
            .lto = switch (options.lto) {
                .none => .None,
                .thin => .ThinPreLink,
                .full => .FullPreLink,
            },
            .allow_fast_isel = true,
            // LLVM's RISC-V backend for some reason enables the machine outliner by default even
            // though it's clearly not ready and produces multiple miscompilations in our std tests.
            .allow_machine_outliner = !comp.root_mod.resolved_target.result.cpu.arch.isRISCV(),
            .asm_filename = null,
            .bin_filename = if (options.bin_path) |x| x.ptr else null,
            .llvm_ir_filename = if (options.post_ir_path) |x| x.ptr else null,
            .bitcode_filename = null,

            // `.coverage` value is only used when `.sancov` is enabled.
            .sancov = options.fuzz or comp.config.san_cov_trace_pc_guard,
            .coverage = .{
                .CoverageType = .Edge,
                // Works in tandem with Inline8bitCounters or InlineBoolFlag.
                // Zig does not yet implement its own version of this but it
                // needs to for better fuzzing logic.
                .IndirectCalls = false,
                .TraceBB = false,
                .TraceCmp = false,
                .TraceDiv = false,
                .TraceGep = false,
                .Use8bitCounters = false,
                .TracePC = false,
                .TracePCGuard = comp.config.san_cov_trace_pc_guard,
                // Zig emits its own inline 8-bit counters instrumentation.
                .Inline8bitCounters = false,
                .InlineBoolFlag = false,
                // Zig emits its own PC table instrumentation.
                .PCTable = false,
                .NoPrune = false,
                // Workaround for https://github.com/llvm/llvm-project/pull/106464
                .StackDepth = true,
                .TraceLoads = false,
                .TraceStores = false,
                .CollectControlFlow = false,
            },
        };
        if (options.asm_path != null and options.bin_path != null) {
            if (target_machine.emitToFile(module, &error_message, &lowered_options)) {
                defer bindings.disposeMessage(error_message);
                return diags.fail("LLVM failed to emit bin={s} ir={s}: {s}", .{
                    emit_bin_msg, post_llvm_ir_msg, error_message,
                });
            }
            lowered_options.bin_filename = null;
            lowered_options.llvm_ir_filename = null;
        }

        var time_report_c_str: [*:0]u8 = undefined;
        if (options.time_report != null) {
            lowered_options.time_report_out = &time_report_c_str;
        }

        lowered_options.asm_filename = if (options.asm_path) |x| x.ptr else null;
        if (target_machine.emitToFile(module, &error_message, &lowered_options)) {
            defer bindings.disposeMessage(error_message);
            return diags.fail("LLVM failed to emit asm={s} bin={s} ir={s} bc={s}: {s}", .{
                emit_asm_msg, emit_bin_msg, post_llvm_ir_msg, post_llvm_bc_msg, error_message,
            });
        }
        if (options.time_report) |tr| {
            defer std.c.free(time_report_c_str);
            const time_report_data = std.mem.span(time_report_c_str);
            assert(tr.llvm_pass_timings.len == 0);
            tr.llvm_pass_timings = try comp.gpa.dupe(u8, time_report_data);
        }
    }

    pub fn updateFunc(
        o: *Object,
        pt: Zcu.PerThread,
        func_index: InternPool.Index,
        air: *const Air,
        liveness: *const ?Air.Liveness,
    ) Zcu.CodegenFailError!void {
        const zcu = o.zcu;
        const comp = zcu.comp;
        const gpa = comp.gpa;
        const ip = &zcu.intern_pool;
        const func = zcu.funcInfo(func_index);
        const nav = ip.getNav(func.owner_nav);
        const file_scope = zcu.navFileScopeIndex(func.owner_nav);
        const owner_mod = zcu.fileByIndex(file_scope).mod.?;
        const fn_ty = Type.fromInterned(func.ty);
        const fn_info = zcu.typeToFunc(fn_ty).?;
        const target = &owner_mod.resolved_target.result;

        const gop = try o.nav_map.getOrPut(gpa, func.owner_nav);
        if (!gop.found_existing) {
            errdefer assert(o.nav_map.remove(func.owner_nav));
            // First time lowering this NAV! Create a fresh global.
            const llvm_name = try o.builder.strtabString(nav.fqn.toSlice(ip));
            gop.value_ptr.* = try o.builder.addGlobal(llvm_name, .{
                .type = .void, // placeholder; populated below
                .kind = .{ .alias = .none }, // placeholder; populated below
            });
        }
        const llvm_global = gop.value_ptr.*;

        const llvm_function: Builder.Function.Index = switch (llvm_global.ptrConst(&o.builder).kind) {
            .function => |function| function, // re-use existing `Builder.Function`
            .replaced, .alias, .variable => try llvm_global.toNewFunction(&o.builder),
        };
        {
            const global = llvm_function.ptrConst(&o.builder).global.ptr(&o.builder);
            global.type = try o.lowerType(fn_ty);
            global.addr_space = toLlvmAddressSpace(nav.resolved.?.@"addrspace", target);
            global.linkage = if (o.builder.strip) .private else .internal;
            global.visibility = .default;
            global.dll_storage_class = .default;
            global.unnamed_addr = .unnamed_addr;
        }
        llvm_function.setAlignment(switch (nav.resolved.?.@"align") {
            .none => fn_ty.abiAlignment(zcu).toLlvm(),
            else => |a| a.toLlvm(),
        }, &o.builder);
        llvm_function.setSection(s: {
            const section = nav.resolved.?.@"linksection".toSlice(ip) orelse break :s .none;
            break :s try o.builder.string(section);
        }, &o.builder);
        try o.addLlvmFunctionAttributes(pt, func.owner_nav, llvm_function);

        var attributes = try llvm_function.ptrConst(&o.builder).attributes.toWip(&o.builder);
        defer attributes.deinit(&o.builder);

        const func_analysis = func.analysisUnordered(ip);
        if (func_analysis.is_noinline) {
            try attributes.addFnAttr(.@"noinline", &o.builder);
        } else {
            _ = try attributes.removeFnAttr(.@"noinline");
        }

        if (func_analysis.branch_hint == .cold) {
            try attributes.addFnAttr(.cold, &o.builder);
        } else {
            _ = try attributes.removeFnAttr(.cold);
        }

        if (owner_mod.sanitize_thread and !func_analysis.disable_instrumentation) {
            try attributes.addFnAttr(.sanitize_thread, &o.builder);
        } else {
            _ = try attributes.removeFnAttr(.sanitize_thread);
        }
        const is_naked = fn_info.cc == .naked;
        if (!func_analysis.disable_instrumentation and !is_naked) {
            if (owner_mod.fuzz) {
                try attributes.addFnAttr(.optforfuzzing, &o.builder);
            }
            _ = try attributes.removeFnAttr(.skipprofile);
            _ = try attributes.removeFnAttr(.nosanitize_coverage);
        } else {
            _ = try attributes.removeFnAttr(.optforfuzzing);
            try attributes.addFnAttr(.skipprofile, &o.builder);
            try attributes.addFnAttr(.nosanitize_coverage, &o.builder);
        }

        const disable_intrinsics = func_analysis.disable_intrinsics or owner_mod.no_builtin;
        if (disable_intrinsics) {
            // The intent here is for compiler-rt and libc functions to not generate
            // infinite recursion. For example, if we are compiling the memcpy function,
            // and llvm detects that the body is equivalent to memcpy, it may replace the
            // body of memcpy with a call to memcpy, which would then cause a stack
            // overflow instead of performing memcpy.
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("no-builtins"),
                .value = .empty,
            } }, &o.builder);
        }

        // TODO: disable this if safety is off for the function scope
        const ssp_buf_size = owner_mod.stack_protector;
        if (ssp_buf_size != 0) {
            try attributes.addFnAttr(.sspstrong, &o.builder);
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("stack-protector-buffer-size"),
                .value = try o.builder.fmt("{d}", .{ssp_buf_size}),
            } }, &o.builder);
        }

        // TODO: disable this if safety is off for the function scope
        if (owner_mod.stack_check) {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("probe-stack"),
                .value = try o.builder.string("__zig_probe_stack"),
            } }, &o.builder);
        } else if (target.os.tag == .uefi) {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("no-stack-arg-probe"),
                .value = .empty,
            } }, &o.builder);
        }

        var deinit_wip = true;
        var wip = try Builder.WipFunction.init(&o.builder, .{
            .function = llvm_function,
            .strip = owner_mod.strip,
        });
        defer if (deinit_wip) wip.deinit();
        wip.cursor = .{ .block = try wip.block(0, "Entry") };

        // This is the list of args we will use that correspond directly to the AIR arg
        // instructions. Depending on the calling convention, this list is not necessarily
        // a bijection with the actual LLVM parameters of the function.
        var args: std.ArrayList(Builder.Value) = .empty;
        defer args.deinit(gpa);

        const ret_ptr: Builder.Value, const err_ret_trace: Builder.Value = implicit_args: {
            var it = iterateParamTypes(o, fn_info);

            const ret_ptr: Builder.Value = if (firstParamSRet(fn_info, zcu, target)) param: {
                const param = wip.arg(it.llvm_index);
                it.llvm_index += 1;
                break :param param;
            } else .none;

            const err_return_tracing = fn_info.cc == .auto and comp.config.any_error_tracing;
            const err_ret_trace: Builder.Value = if (err_return_tracing) param: {
                const param = wip.arg(it.llvm_index);
                it.llvm_index += 1;
                break :param param;
            } else .none;

            while (try it.next()) |lowering| {
                try args.ensureUnusedCapacity(gpa, 1);

                switch (lowering) {
                    .no_bits => continue,
                    .byval => {
                        assert(!it.byval_attr);
                        const param_index = it.zig_index - 1;
                        const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[param_index]);
                        const param = wip.arg(it.llvm_index - 1);

                        if (isByRef(param_ty, zcu)) {
                            const alignment = param_ty.abiAlignment(zcu).toLlvm();
                            const param_llvm_ty = param.typeOfWip(&wip);
                            const arg_ptr = try buildAllocaInner(&wip, param_llvm_ty, alignment, target);
                            _ = try wip.store(.normal, param, arg_ptr, alignment);
                            args.appendAssumeCapacity(arg_ptr);
                        } else {
                            args.appendAssumeCapacity(param);
                        }
                    },
                    .byref => {
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param = wip.arg(it.llvm_index - 1);

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(param);
                        } else {
                            const param_llvm_ty = try o.lowerType(param_ty);
                            const alignment = param_ty.abiAlignment(zcu).toLlvm();
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, param, alignment, ""));
                        }
                    },
                    .byref_mut => {
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param = wip.arg(it.llvm_index - 1);

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(param);
                        } else {
                            const param_llvm_ty = try o.lowerType(param_ty);
                            const alignment = param_ty.abiAlignment(zcu).toLlvm();
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, param, alignment, ""));
                        }
                    },
                    .abi_sized_int => {
                        assert(!it.byval_attr);
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param = wip.arg(it.llvm_index - 1);

                        const param_llvm_ty = try o.lowerType(param_ty);
                        const alignment = param_ty.abiAlignment(zcu).toLlvm();
                        const arg_ptr = try buildAllocaInner(&wip, param_llvm_ty, alignment, target);
                        _ = try wip.store(.normal, param, arg_ptr, alignment);

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(arg_ptr);
                        } else {
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, arg_ptr, alignment, ""));
                        }
                    },
                    .slice => {
                        assert(!it.byval_attr);
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        assert(!isByRef(param_ty, zcu));
                        const slice_val = try wip.buildAggregate(
                            try o.lowerType(param_ty),
                            &.{ wip.arg(it.llvm_index - 2), wip.arg(it.llvm_index - 1) },
                            "",
                        );
                        args.appendAssumeCapacity(slice_val);
                    },
                    .multiple_llvm_types => {
                        assert(!it.byval_attr);
                        const field_types = it.types_buffer[0..it.types_len];
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param_llvm_ty = try o.lowerType(param_ty);
                        const param_alignment = param_ty.abiAlignment(zcu).toLlvm();
                        const arg_ptr = try buildAllocaInner(&wip, param_llvm_ty, param_alignment, target);
                        const llvm_ty = try o.builder.structType(.normal, field_types);
                        const llvm_args_start = it.llvm_index - field_types.len;
                        for (0..field_types.len, llvm_args_start..) |field_i, llvm_arg_index| {
                            const param = wip.arg(@intCast(llvm_arg_index));
                            const field_ptr = try wip.gepStruct(llvm_ty, arg_ptr, field_i, "");
                            const alignment: Builder.Alignment = .fromByteUnits(@divExact(target.ptrBitWidth(), 8));
                            _ = try wip.store(.normal, param, field_ptr, alignment);
                        }

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(arg_ptr);
                        } else {
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, arg_ptr, param_alignment, ""));
                        }
                    },
                    .float_array => {
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param_llvm_ty = try o.lowerType(param_ty);
                        const param = wip.arg(it.llvm_index - 1);

                        const alignment = param_ty.abiAlignment(zcu).toLlvm();
                        const arg_ptr = try buildAllocaInner(&wip, param_llvm_ty, alignment, target);
                        _ = try wip.store(.normal, param, arg_ptr, alignment);

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(arg_ptr);
                        } else {
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, arg_ptr, alignment, ""));
                        }
                    },
                    .i32_array, .i64_array => {
                        const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                        const param_llvm_ty = try o.lowerType(param_ty);
                        const param = wip.arg(it.llvm_index - 1);

                        const alignment = param_ty.abiAlignment(zcu).toLlvm();
                        const arg_ptr = try buildAllocaInner(&wip, param.typeOfWip(&wip), alignment, target);
                        _ = try wip.store(.normal, param, arg_ptr, alignment);

                        if (isByRef(param_ty, zcu)) {
                            args.appendAssumeCapacity(arg_ptr);
                        } else {
                            args.appendAssumeCapacity(try wip.load(.normal, param_llvm_ty, arg_ptr, alignment, ""));
                        }
                    },
                }
            }

            break :implicit_args .{ ret_ptr, err_ret_trace };
        };

        const file, const subprogram = if (!wip.strip) debug_info: {
            const file = try o.getDebugFile(file_scope);

            const line_number = zcu.navSrcLine(func.owner_nav) + 1;
            const is_internal_linkage = ip.indexToKey(nav.resolved.?.value) != .@"extern";
            const debug_decl_type = try o.getDebugType(pt, fn_ty);

            const subprogram = try o.builder.debugSubprogram(
                file,
                try o.builder.metadataString(nav.name.toSlice(ip)),
                try o.builder.metadataString(nav.fqn.toSlice(ip)),
                line_number,
                line_number + func.lbrace_line,
                debug_decl_type,
                .{
                    .di_flags = .{
                        .StaticMember = true,
                        .NoReturn = fn_info.return_type == .noreturn_type,
                    },
                    .sp_flags = .{
                        .Optimized = owner_mod.optimize_mode != .Debug,
                        .Definition = true,
                        .LocalToUnit = is_internal_linkage,
                    },
                },
                o.debug_compile_unit.unwrap().?,
            );
            llvm_function.setSubprogram(subprogram, &o.builder);
            break :debug_info .{ file, subprogram };
        } else .{undefined} ** 2;

        const fuzz: ?FuncGen.Fuzz = f: {
            if (!owner_mod.fuzz) break :f null;
            if (func_analysis.disable_instrumentation) break :f null;
            if (is_naked) break :f null;
            if (comp.config.san_cov_trace_pc_guard) break :f null;

            // The void type used here is a placeholder to be replaced with an
            // array of the appropriate size after the POI count is known.

            // Due to error "members of llvm.compiler.used must be named", this global needs a name.
            const anon_name = try o.builder.strtabStringFmt("__sancov_gen_.{d}", .{o.used.items.len});
            const counters_variable = try o.builder.addVariable(anon_name, .void, .default);
            try o.used.append(gpa, counters_variable.toConst(&o.builder));
            counters_variable.ptrConst(&o.builder).global.setLinkage(.private, &o.builder);
            counters_variable.setAlignment(comptime Builder.Alignment.fromByteUnits(1), &o.builder);

            if (target.ofmt == .macho) {
                counters_variable.setSection(try o.builder.string("__DATA,__sancov_cntrs"), &o.builder);
            } else {
                counters_variable.setSection(try o.builder.string("__sancov_cntrs"), &o.builder);
            }

            break :f .{
                .counters_variable = counters_variable,
                .pcs = .empty,
            };
        };

        var fg: FuncGen = .{
            .object = o,
            .nav_index = func.owner_nav,
            .pt = pt,
            .gpa = gpa,
            .air = air.*,
            .liveness = liveness.*.?,
            .wip = wip,
            .is_naked = fn_info.cc == .naked,
            .fuzz = fuzz,
            .ret_ptr = ret_ptr,
            .args = args.items,
            .arg_index = 0,
            .arg_inline_index = 0,
            .func_inst_table = .empty,
            .blocks = .empty,
            .loops = .empty,
            .switch_dispatch_info = .empty,
            .sync_scope = if (owner_mod.single_threaded) .singlethread else .system,
            .file = file,
            .scope = subprogram,
            .inlined_at = .none,
            .base_line = zcu.navSrcLine(func.owner_nav),
            .prev_dbg_line = 0,
            .prev_dbg_column = 0,
            .err_ret_trace = err_ret_trace,
            .disable_intrinsics = disable_intrinsics,
            .allowzero_access = false,
        };
        defer fg.deinit();
        deinit_wip = false;

        try fg.genBody(air.getMainBody(), .poi);

        // If we saw any loads or stores involving `allowzero` pointers, we need to mark the whole
        // function as considering null pointers valid so that LLVM's optimizers don't remove these
        // operations on the assumption that they're undefined behavior.
        if (fg.allowzero_access) {
            try attributes.addFnAttr(.null_pointer_is_valid, &o.builder);
        } else {
            _ = try attributes.removeFnAttr(.null_pointer_is_valid);
        }

        llvm_function.setAttributes(try attributes.finish(&o.builder), &o.builder);

        if (fg.fuzz) |*f| {
            {
                const array_llvm_ty = try o.builder.arrayType(f.pcs.items.len, .i8);
                f.counters_variable.ptrConst(&o.builder).global.ptr(&o.builder).type = array_llvm_ty;
                const zero_init = try o.builder.zeroInitConst(array_llvm_ty);
                try f.counters_variable.setInitializer(zero_init, &o.builder);
            }

            const array_llvm_ty = try o.builder.arrayType(f.pcs.items.len, .ptr);
            const init_val = try o.builder.arrayConst(array_llvm_ty, f.pcs.items);
            // Due to error "members of llvm.compiler.used must be named", this global needs a name.
            const anon_name = try o.builder.strtabStringFmt("__sancov_gen_.{d}", .{o.used.items.len});
            const pcs_variable = try o.builder.addVariable(anon_name, array_llvm_ty, .default);
            try pcs_variable.setInitializer(init_val, &o.builder);
            pcs_variable.setMutability(.constant, &o.builder);
            pcs_variable.setSection(switch (target.ofmt) {
                .macho => try o.builder.string("__DATA,__sancov_pcs1"),
                else => try o.builder.string("__sancov_pcs1"),
            }, &o.builder);
            pcs_variable.setAlignment(Type.usize.abiAlignment(zcu).toLlvm(), &o.builder);
            const pcs_global = pcs_variable.ptrConst(&o.builder).global;
            pcs_global.setLinkage(.private, &o.builder);
            try o.used.append(gpa, pcs_global.toConst());
        }

        try fg.wip.finish();
        try o.flushTypePool(pt);
    }

    pub fn updateNav(o: *Object, pt: Zcu.PerThread, nav_id: InternPool.Nav.Index) !void {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const comp = zcu.comp;
        const gpa = comp.gpa;

        const nav = ip.getNav(nav_id);
        const resolved = nav.resolved.?;

        const opt_extern: ?InternPool.Key.Extern = switch (ip.indexToKey(resolved.value)) {
            .@"extern" => |@"extern"| @"extern",
            else => null,
        };
        const nav_ty: Type = .fromInterned(resolved.type);
        const llvm_ty: Builder.Type = if (opt_extern != null) ty: {
            // We *must* lower this declaration no matter what. If it has a type we can't actually
            // represent (because it doesn't have runtime bits), we instead lower as the zero-size
            // type `[0 x i8]`. I don't think the type on an extern declaration actually does much
            // anyway.
            if (nav_ty.isRuntimeFnOrHasRuntimeBits(zcu)) break :ty try o.lowerType(nav_ty);
            break :ty try o.builder.arrayType(0, .i8);
        } else if (nav_ty.hasRuntimeBits(zcu)) ty: {
            break :ty try o.lowerType(nav_ty);
        } else {
            // This is a non-extern zero-bit `Nav`---we're not interested in it.
            // TODO: we might need to rethink this a little under incremental compilation. If a
            // declaration becomes zero-bit, we can't just leave its old value there, because it
            // might now be ill-formed.
            return;
        };

        const gop = try o.nav_map.getOrPut(gpa, nav_id);
        if (!gop.found_existing) {
            errdefer assert(o.nav_map.remove(nav_id));
            // First time lowering this NAV! Create a fresh global.
            const llvm_name = try o.builder.strtabString(nav.fqn.toSlice(ip));
            gop.value_ptr.* = try o.builder.addGlobal(llvm_name, .{
                .type = .void, // placeholder; populated below
                .kind = .{ .alias = .none }, // placeholder; populated below
            });
        }
        const llvm_global = gop.value_ptr.*;

        llvm_global.ptr(&o.builder).type = llvm_ty;
        llvm_global.ptr(&o.builder).addr_space = toLlvmAddressSpace(resolved.@"addrspace", zcu.getTarget());

        if (opt_extern) |@"extern"| {
            const name = name: {
                const name_slice = nav.name.toSlice(ip);
                if (zcu.getTarget().cpu.arch.isWasm() and nav_ty.zigTypeTag(zcu) == .@"fn") {
                    if (@"extern".lib_name.toSlice(ip)) |lib_name_slice| {
                        if (!std.mem.eql(u8, lib_name_slice, "c")) {
                            break :name try o.builder.strtabStringFmt("{s}|{s}", .{ name_slice, lib_name_slice });
                        }
                    }
                }
                break :name try o.builder.strtabString(name_slice);
            };
            if (o.builder.getGlobal(name)) |other_global| {
                if (other_global != llvm_global) {
                    // Another global already has this name; just use it in place of this global.
                    try llvm_global.replace(other_global, &o.builder);
                    return;
                }
            }
            try llvm_global.rename(name, &o.builder);
            llvm_global.ptr(&o.builder).unnamed_addr = .default;
            llvm_global.ptr(&o.builder).dll_storage_class = switch (@"extern".is_dll_import) {
                true => .dllimport,
                false => .default,
            };
            llvm_global.ptr(&o.builder).linkage = switch (@"extern".linkage) {
                .internal => if (o.builder.strip) .private else .internal,
                .strong => .external,
                .weak => .extern_weak,
                .link_once => unreachable,
            };
            llvm_global.ptr(&o.builder).visibility = .fromSymbolVisibility(@"extern".visibility);
        } else {
            llvm_global.ptr(&o.builder).linkage = if (o.builder.strip) .private else .internal;
            llvm_global.ptr(&o.builder).visibility = .default;
            llvm_global.ptr(&o.builder).dll_storage_class = .default;
            llvm_global.ptr(&o.builder).unnamed_addr = .unnamed_addr;
        }

        const llvm_align = switch (resolved.@"align") {
            .none => nav_ty.abiAlignment(zcu).toLlvm(),
            else => |a| a.toLlvm(),
        };
        const llvm_section: Builder.String = if (resolved.@"linksection".toSlice(ip)) |section| s: {
            break :s try o.builder.string(section);
        } else .none;

        // Actual function bodies with AIR go through `updateFunc` instead, so the only functions we
        // can see are extern functions or other comptime function body values (e.g. undefined). Of
        // these, only extern functions need to be lowered to LLVM functions.
        if (opt_extern != null and nav_ty.zigTypeTag(zcu) == .@"fn" and nav_ty.fnHasRuntimeBits(zcu)) {
            const llvm_function: Builder.Function.Index = switch (llvm_global.ptrConst(&o.builder).kind) {
                .function => |function| function, // re-use existing `Builder.Function`
                .replaced, .alias, .variable => try llvm_global.toNewFunction(&o.builder),
            };
            llvm_function.setAlignment(llvm_align, &o.builder);
            llvm_function.setSection(llvm_section, &o.builder);
            try o.addLlvmFunctionAttributes(pt, nav_id, llvm_function);
        } else {
            const file_scope = nav.srcInst(ip).resolveFile(ip);
            const mod = zcu.fileByIndex(file_scope).mod.?;

            const llvm_variable: Builder.Variable.Index = switch (llvm_global.ptrConst(&o.builder).kind) {
                .variable => |variable| variable, // re-use existing `Builder.Variable`
                .replaced, .alias, .function => try llvm_global.toNewVariable(&o.builder),
            };
            llvm_variable.setAlignment(llvm_align, &o.builder);
            llvm_variable.setSection(llvm_section, &o.builder);
            llvm_variable.setMutability(if (resolved.@"const") .constant else .global, &o.builder);
            try llvm_variable.setInitializer(if (opt_extern != null) .no_init else try o.lowerValue(resolved.value), &o.builder);
            llvm_variable.setThreadLocal(tl: {
                if (resolved.@"threadlocal" and !mod.single_threaded) break :tl .generaldynamic;
                break :tl .default;
            }, &o.builder);

            if (!mod.strip) {
                const debug_file = try o.getDebugFile(file_scope);
                const debug_global_var_expr = try o.builder.debugGlobalVarExpression(
                    try o.builder.debugGlobalVar(
                        try o.builder.metadataString(nav.name.toSlice(ip)), // Name
                        try o.builder.metadataString(nav.fqn.toSlice(ip)), // Linkage name
                        debug_file, // File
                        debug_file, // Scope
                        zcu.navSrcLine(nav_id) + 1,
                        try o.getDebugType(pt, nav_ty),
                        llvm_variable,
                        .{ .local = llvm_global.ptrConst(&o.builder).linkage == .internal },
                    ),
                    try o.builder.debugExpression(&.{}),
                );
                llvm_variable.setGlobalVariableExpression(debug_global_var_expr, &o.builder);
                try o.debug_globals.append(o.gpa, debug_global_var_expr);
            }
        }
    }

    fn flushTypePool(o: *Object, pt: Zcu.PerThread) Allocator.Error!void {
        try o.type_pool.flushPending(pt, .{ .llvm = o });
    }

    pub fn updateExports(
        o: *Object,
        exported: Zcu.Exported,
        export_indices: []const Zcu.Export.Index,
    ) link.File.UpdateExportsError!void {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const ty: Type, const llvm_ptr: Builder.Constant = switch (exported) {
            .nav => |nav| exp: {
                const nav_ty: Type = .fromInterned(ip.getNav(nav).resolved.?.type);
                const nav_ref = try o.lowerNavRef(nav);
                break :exp .{ nav_ty, nav_ref };
            },
            .uav => |uav| exp: {
                const uav_ty = Value.fromInterned(uav).typeOf(zcu);
                const uav_ref = try o.lowerUavRef(
                    uav,
                    uav_ty.abiAlignment(zcu),
                    target_util.defaultAddressSpace(zcu.getTarget(), .global_constant),
                );
                break :exp .{ uav_ty, uav_ref };
            },
        };
        switch (llvm_ptr.unwrap()) {
            .global => |global| return o.updateExportedGlobal(global, ty, export_indices),
            .constant => @panic("LLVM TODO: export zero-bit value"),
        }
    }

    fn updateExportedGlobal(
        o: *Object,
        global_index: Builder.Global.Index,
        ty: Type,
        export_indices: []const Zcu.Export.Index,
    ) link.File.UpdateExportsError!void {
        const zcu = o.zcu;
        const comp = zcu.comp;
        const ip = &zcu.intern_pool;

        // If we're on COFF and linking with LLD, the linker cares about our exports to determine the subsystem in use.
        coff_export_flags: {
            const lf = comp.bin_file orelse break :coff_export_flags;
            const lld = lf.cast(.lld) orelse break :coff_export_flags;
            const coff = switch (lld.ofmt) {
                .elf, .wasm => break :coff_export_flags,
                .coff => |*coff| coff,
            };
            if (ty.zigTypeTag(zcu) != .@"fn") break :coff_export_flags;
            const flags = &coff.lld_export_flags;
            for (export_indices) |export_index| {
                const name = export_index.ptr(zcu).opts.name;
                if (name.eqlSlice("main", ip)) flags.c_main = true;
                if (name.eqlSlice("WinMain", ip)) flags.winmain = true;
                if (name.eqlSlice("wWinMain", ip)) flags.wwinmain = true;
                if (name.eqlSlice("WinMainCRTStartup", ip)) flags.winmain_crt_startup = true;
                if (name.eqlSlice("wWinMainCRTStartup", ip)) flags.wwinmain_crt_startup = true;
                if (name.eqlSlice("DllMainCRTStartup", ip)) flags.dllmain_crt_startup = true;
            }
        }

        // If the first export specifies a linksection, set the exported variable's section to that
        // one. This is kind of a hack because `std.builtin.ExportOptions.section` doesn't actually
        // make much sense: the linksection should be associated with the declaration itself rather
        // than some particular symbol it is exported as!
        if (export_indices[0].ptr(zcu).opts.section.toSlice(ip)) |section_slice| {
            const variable = &global_index.ptrConst(&o.builder).kind.variable;
            variable.setSection(try o.builder.string(section_slice), &o.builder);
        }

        const llvm_global_ty = global_index.typeOf(&o.builder);

        // All exports are represented as aliases to the original global.

        // TODO: we currently do not delete old exports. To do that we'll need to track which
        // globals actually *are* exports.

        for (export_indices) |export_idx| {
            const exp = export_idx.ptr(zcu);
            const exp_name = try o.builder.strtabString(exp.opts.name.toSlice(ip));

            // Our goal is to make an alias with the name `exp_name`, but if that name is already
            // taken by some existing global, we need to figure out what to do with that existing
            // global.
            //
            // The name, aliasee, and type will be set within this block. Other properties of the
            // alias will be set below.
            const alias_global: Builder.Global.Index = global: {
                const existing_global = o.builder.getGlobal(exp_name) orelse {
                    // There is no existing global with this name, so make a new alias.
                    const alias = try o.builder.addAlias(
                        exp_name,
                        llvm_global_ty,
                        .default,
                        global_index.toConst(),
                    );
                    break :global alias.ptrConst(&o.builder).global;
                };
                // There is an existing global with this name, so we can't just create an alias. We
                // need to figure out what to do with the existing global instead.
                switch (existing_global.ptrConst(&o.builder).kind) {
                    .alias => |alias| {
                        // We can just repurpose the existing alias.
                        alias.setAliasee(global_index.toConst(), &o.builder);
                        alias.ptrConst(&o.builder).global.ptr(&o.builder).type = global_index.typeOf(&o.builder);
                        break :global existing_global;
                    },
                    .variable, .function => {
                        // This must be an extern, which is no good to us---we need an alias. The
                        // extern should refer to the value we're exporting, so replace it with the
                        // exported value. That will free up the name for us to create a new alias.
                        // We need to make a new global which is an alias. Replace this existing one
                        // with the target global, making the name available and fixing references
                        // to this global to point to the target.
                        try existing_global.replace(global_index, &o.builder);
                        // The name is now free, so create an alias.
                        const alias = try o.builder.addAlias(
                            exp_name,
                            llvm_global_ty,
                            .default,
                            global_index.toConst(),
                        );
                        break :global alias.ptrConst(&o.builder).global;
                    },
                    .replaced => unreachable, // a replaced global would have lost the name `exp_name`
                }
            };

            // Now for a bit of setup which

            // We need the alias to *not* be `unnamed_addr` to ensure that the alias address equals
            // the address of the original global.
            alias_global.setUnnamedAddr(.default, &o.builder);

            if (comp.config.dll_export_fns and exp.opts.visibility != .hidden)
                alias_global.setDllStorageClass(.dllexport, &o.builder);
            alias_global.setLinkage(switch (exp.opts.linkage) {
                .internal => if (o.builder.strip) .private else .internal, // we still did useful work in replacing an existing symbol if there was one
                .strong => .external,
                .weak => .weak_odr,
                .link_once => .linkonce_odr,
            }, &o.builder);
            alias_global.setVisibility(switch (exp.opts.visibility) {
                .default => .default,
                .hidden => .hidden,
                .protected => .protected,
            }, &o.builder);
        }
    }

    pub fn updateContainerType(o: *Object, pt: Zcu.PerThread, ty: InternPool.Index, success: bool) Allocator.Error!void {
        try o.type_pool.updateContainerType(pt, .{ .llvm = o }, ty, success);
        if (o.named_enum_map.get(ty)) |function_index| {
            try o.updateIsNamedEnumValueFunction(.fromInterned(ty), function_index);
        }
        if (o.enum_tag_name_map.get(ty)) |function_index| {
            try o.updateEnumTagNameFunction(.fromInterned(ty), function_index);
        }
    }

    /// Should only be called by the `link.ConstPool` implementation.
    ///
    /// `val` is always a type because `o.type_pool` only contains types.
    pub fn addConst(o: *Object, pt: Zcu.PerThread, index: link.ConstPool.Index, val: InternPool.Index) Allocator.Error!void {
        _ = pt;
        const zcu = o.zcu;
        const gpa = zcu.comp.gpa;
        assert(zcu.intern_pool.typeOf(val) == .type_type);

        {
            assert(@intFromEnum(index) == o.lazy_abi_aligns.items.len);
            try o.lazy_abi_aligns.ensureUnusedCapacity(gpa, 1);
            const fwd_ref = try o.builder.alignmentForwardReference();
            o.lazy_abi_aligns.appendAssumeCapacity(fwd_ref);
        }

        if (!o.builder.strip) {
            assert(@intFromEnum(index) == o.debug_types.items.len);
            try o.debug_types.ensureUnusedCapacity(gpa, 1);
            const fwd_ref = try o.builder.debugForwardReference();
            o.debug_types.appendAssumeCapacity(fwd_ref);
            if (val == .anyerror_type) {
                assert(o.debug_anyerror_fwd_ref.is_none);
                o.debug_anyerror_fwd_ref = fwd_ref.toOptional();
            }
        }
    }
    /// Should only be called by the `link.ConstPool` implementation.
    ///
    /// `val` is always a type because `o.type_pool` only contains types.
    pub fn updateConstIncomplete(o: *Object, pt: Zcu.PerThread, index: link.ConstPool.Index, val: InternPool.Index) Allocator.Error!void {
        const zcu = o.zcu;
        assert(zcu.intern_pool.typeOf(val) == .type_type);

        const ty: Type = .fromInterned(val);

        {
            const fwd_ref = o.lazy_abi_aligns.items[@intFromEnum(index)];
            o.builder.resolveAlignmentForwardReference(fwd_ref, .fromByteUnits(1));
        }

        if (!o.builder.strip) {
            assert(val != .anyerror_type);
            const fwd_ref = o.debug_types.items[@intFromEnum(index)];
            const name_str = try o.builder.metadataStringFmt("{f}", .{ty.fmt(pt)});
            // If `ty` is a function, use a dummy *function* type to prevent existing debug
            // subprograms from becoming ill-formed.
            const debug_incomplete_type = switch (ty.zigTypeTag(zcu)) {
                .@"fn" => try o.builder.debugSubroutineType(null),
                else => try o.builder.debugSignedType(name_str, 0),
            };
            o.builder.resolveDebugForwardReference(fwd_ref, debug_incomplete_type);
        }
    }
    /// Should only be called by the `link.ConstPool` implementation.
    ///
    /// `val` is always a type because `o.type_pool` only contains types.
    pub fn updateConst(o: *Object, pt: Zcu.PerThread, index: link.ConstPool.Index, val: InternPool.Index) Allocator.Error!void {
        const zcu = o.zcu;
        assert(zcu.intern_pool.typeOf(val) == .type_type);

        const ty: Type = .fromInterned(val);

        {
            const fwd_ref = o.lazy_abi_aligns.items[@intFromEnum(index)];
            o.builder.resolveAlignmentForwardReference(fwd_ref, ty.abiAlignment(zcu).toLlvm());
        }

        if (!o.builder.strip) {
            const fwd_ref = o.debug_types.items[@intFromEnum(index)];
            if (val == .anyerror_type) {
                // Don't lower this now; it will be populated in `emit` instead.
                assert(o.debug_anyerror_fwd_ref == fwd_ref.toOptional());
            } else {
                const debug_type = try o.lowerDebugType(pt, ty, fwd_ref);
                o.builder.resolveDebugForwardReference(fwd_ref, debug_type);
            }
        }
    }

    pub fn getDebugFile(o: *Object, file_index: Zcu.File.Index) Allocator.Error!Builder.Metadata {
        const gpa = o.gpa;
        const gop = try o.debug_file_map.getOrPut(gpa, file_index);
        errdefer assert(o.debug_file_map.remove(file_index));
        if (gop.found_existing) return gop.value_ptr.*;
        const path = o.zcu.fileByIndex(file_index).path;
        const abs_path = try path.toAbsolute(o.zcu.comp.dirs, gpa);
        defer gpa.free(abs_path);

        gop.value_ptr.* = try o.builder.debugFile(
            try o.builder.metadataString(std.fs.path.basename(abs_path)),
            try o.builder.metadataString(std.fs.path.dirname(abs_path) orelse ""),
        );
        return gop.value_ptr.*;
    }

    pub fn getDebugType(o: *Object, pt: Zcu.PerThread, ty: Type) Allocator.Error!Builder.Metadata {
        assert(!o.builder.strip);
        const index = try o.type_pool.get(pt, .{ .llvm = o }, ty.toIntern());
        return o.debug_types.items[@intFromEnum(index)];
    }

    /// In codegen logic, instead of calling this directly, use `getDebugType` to get a forward
    /// reference which will be populated only when all necessary type resolution is complete.
    fn lowerDebugType(
        o: *Object,
        pt: Zcu.PerThread,
        ty: Type,
        ty_fwd_ref: Builder.Metadata,
    ) Allocator.Error!Builder.Metadata {
        assert(!o.builder.strip);

        const gpa = o.gpa;
        const zcu = o.zcu;
        const target = zcu.getTarget();
        const ip = &zcu.intern_pool;

        const name = try o.builder.metadataStringFmt("{f}", .{ty.fmt(pt)});

        // lldb cannot handle non-byte-sized types, so in the logic below, bit sizes are padded up.
        // For instance, `bool` is considered to be 8 bits, and `u60` is considered to be 64 bits.

        // I tried using variants (DW_TAG_variant_part + DW_TAG_variant) to encode error unions,
        // tagged unions, etc; this would have told debuggers which field was active, which could
        // improve UX significantly. GDB handles this perfectly fine, but unfortunately, LLDB has no
        // handling for variants at all, and will never print fields in them, so I opted not to use
        // them for now.

        switch (ty.zigTypeTag(zcu)) {
            .void,
            .noreturn,
            .comptime_int,
            .comptime_float,
            .type,
            .undefined,
            .null,
            .enum_literal,
            => return o.builder.debugSignedType(name, 0),

            .float => return o.builder.debugFloatType(name, ty.floatBits(target)),

            .bool => return o.builder.debugBoolType(name, 8),

            .int => {
                const info = ty.intInfo(zcu);
                const bits = ty.abiSize(zcu) * 8;
                return switch (info.signedness) {
                    .signed => try o.builder.debugSignedType(name, bits),
                    .unsigned => try o.builder.debugUnsignedType(name, bits),
                };
            },

            .pointer => {
                const ptr_size = Type.ptrAbiSize(zcu.getTarget());
                const ptr_align = Type.ptrAbiAlignment(zcu.getTarget());

                if (ty.isSlice(zcu)) {
                    const debug_ptr_type = try o.builder.debugMemberType(
                        try o.builder.metadataString("ptr"),
                        null, // file
                        ty_fwd_ref,
                        0, // line
                        try o.getDebugType(pt, ty.slicePtrFieldType(zcu)),
                        ptr_size * 8,
                        ptr_align.toByteUnits().? * 8,
                        0, // offset
                    );

                    const debug_len_type = try o.builder.debugMemberType(
                        try o.builder.metadataString("len"),
                        null, // file
                        ty_fwd_ref,
                        0, // line
                        try o.getDebugType(pt, .usize),
                        ptr_size * 8,
                        ptr_align.toByteUnits().? * 8,
                        ptr_size * 8,
                    );

                    return o.builder.debugStructType(
                        name,
                        null, // file
                        o.debug_compile_unit.unwrap().?, // scope
                        0, // line
                        null, // underlying type
                        ptr_size * 2 * 8,
                        ptr_align.toByteUnits().? * 8,
                        try o.builder.metadataTuple(&.{
                            debug_ptr_type,
                            debug_len_type,
                        }),
                    );
                }

                return o.builder.debugPointerType(
                    name,
                    null, // file
                    o.debug_compile_unit.unwrap().?, // scope
                    0, // line
                    try o.getDebugType(pt, ty.childType(zcu)),
                    ptr_size * 8,
                    ptr_align.toByteUnits().? * 8,
                    0, // offset
                );
            },
            .array => return o.builder.debugArrayType(
                name,
                null, // file
                o.debug_compile_unit.unwrap().?, // scope
                0, // line
                try o.getDebugType(pt, ty.childType(zcu)),
                ty.abiSize(zcu) * 8,
                ty.abiAlignment(zcu).toByteUnits().? * 8,
                try o.builder.metadataTuple(&.{
                    try o.builder.debugSubrange(
                        try o.builder.metadataConstant(try o.builder.intConst(.i64, 0)),
                        try o.builder.metadataConstant(try o.builder.intConst(.i64, ty.arrayLen(zcu))),
                    ),
                }),
            ),
            .vector => {
                const elem_ty = ty.childType(zcu);
                // Vector elements cannot be padded since that would make
                // @bitSizeOf(elem) * len > @bitSizOf(vec).
                // Neither gdb nor lldb seem to be able to display non-byte sized
                // vectors properly.
                const debug_elem_type = switch (elem_ty.zigTypeTag(zcu)) {
                    .int => blk: {
                        const info = elem_ty.intInfo(zcu);
                        break :blk switch (info.signedness) {
                            .signed => try o.builder.debugSignedType(name, info.bits),
                            .unsigned => try o.builder.debugUnsignedType(name, info.bits),
                        };
                    },
                    .bool => try o.builder.debugBoolType(try o.builder.metadataString("bool"), 1),
                    // We don't pad pointers or floats, so we can lower those normally.
                    .pointer, .optional, .float => try o.getDebugType(pt, elem_ty),
                    else => unreachable,
                };

                return o.builder.debugVectorType(
                    name,
                    null, // file
                    o.debug_compile_unit.unwrap().?, // scope
                    0, // line
                    debug_elem_type,
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(&.{
                        try o.builder.debugSubrange(
                            try o.builder.metadataConstant(try o.builder.intConst(.i64, 0)),
                            try o.builder.metadataConstant(try o.builder.intConst(.i64, ty.vectorLen(zcu))),
                        ),
                    }),
                );
            },
            .optional => {
                const payload_ty = ty.optionalChild(zcu);
                if (ty.optionalReprIsPayload(zcu)) {
                    return o.builder.debugTypedefType(
                        name,
                        null, // file
                        o.debug_compile_unit.unwrap().?, // scope
                        0, // line
                        try o.getDebugType(pt, payload_ty),
                        ty.abiSize(zcu) * 8,
                        ty.abiAlignment(zcu).toByteUnits().? * 8,
                        0, // offset
                    );
                }

                const payload_size = payload_ty.abiSize(zcu);

                const non_null_ty = Type.u8;
                const non_null_size = non_null_ty.abiSize(zcu);
                const non_null_align = non_null_ty.abiAlignment(zcu);
                const non_null_offset = non_null_align.forward(payload_size);

                const debug_payload_type = try o.builder.debugMemberType(
                    try o.builder.metadataString("payload"),
                    null, // file
                    ty_fwd_ref, // scope
                    0, // line
                    try o.getDebugType(pt, payload_ty),
                    payload_size * 8,
                    payload_ty.abiAlignment(zcu).toByteUnits().? * 8,
                    0, // offset
                );

                const debug_some_type = try o.builder.debugMemberType(
                    try o.builder.metadataString("some"),
                    null,
                    ty_fwd_ref,
                    0,
                    try o.getDebugType(pt, non_null_ty),
                    non_null_size * 8,
                    non_null_align.toByteUnits().? * 8,
                    non_null_offset * 8,
                );

                return o.builder.debugStructType(
                    name,
                    null, // file
                    o.debug_compile_unit.unwrap().?, // scope
                    0, // line
                    null, // underlying type
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(&.{
                        debug_payload_type,
                        debug_some_type,
                    }),
                );
            },
            .error_union => {
                const error_ty = ty.errorUnionSet(zcu);
                const payload_ty = ty.errorUnionPayload(zcu);

                const error_size = error_ty.abiSize(zcu);
                const error_align = error_ty.abiAlignment(zcu);
                const payload_size = payload_ty.abiSize(zcu);
                const payload_align = payload_ty.abiAlignment(zcu);

                const error_offset: u64, const payload_offset: u64 = offsets: {
                    if (error_align.compare(.gt, payload_align)) {
                        break :offsets .{ 0, payload_align.forward(error_size) };
                    } else {
                        break :offsets .{ error_align.forward(payload_size), 0 };
                    }
                };

                const error_field = try o.builder.debugMemberType(
                    try o.builder.metadataString("error"),
                    null, // file
                    ty_fwd_ref,
                    0, // line
                    try o.getDebugType(pt, error_ty),
                    error_size * 8,
                    error_align.toByteUnits().? * 8,
                    error_offset * 8,
                );
                const payload_field = try o.builder.debugMemberType(
                    try o.builder.metadataString("payload"),
                    null, // file
                    ty_fwd_ref, // scope
                    0, // line
                    try o.getDebugType(pt, payload_ty),
                    payload_size * 8,
                    payload_align.toByteUnits().? * 8,
                    payload_offset * 8,
                );

                return try o.builder.debugStructType(
                    name,
                    null, // File
                    o.debug_compile_unit.unwrap().?, // Scope
                    0, // Line
                    null, // Underlying type
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(&.{ error_field, payload_field }),
                );
            },
            .error_set => {
                assert(ty.toIntern() != .anyerror_type); // handled specially in `updateConst`; will be populated by `emit` instead
                // Error sets are just named wrappers around `anyerror`.
                return o.builder.debugTypedefType(
                    name,
                    null, // file
                    o.debug_compile_unit.unwrap().?, // scope
                    0, // line
                    try o.getDebugType(pt, .anyerror),
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    0, // offset
                );
            },
            .@"fn" => {
                if (!ty.fnHasRuntimeBits(zcu)) {
                    // Use a dummy *function* type to prevent existing debug subprograms from
                    // becoming ill-formed.
                    return o.builder.debugSubroutineType(null);
                }

                const fn_info = zcu.typeToFunc(ty).?;

                var debug_param_types: std.ArrayList(Builder.Metadata) = try .initCapacity(gpa, 3 + fn_info.param_types.len);
                defer debug_param_types.deinit(gpa);

                // Return type goes first.
                if (firstParamSRet(fn_info, zcu, target)) {
                    // Actual return type is void, then first arg is the sret pointer.
                    const ptr_ty = try pt.singleMutPtrType(.fromInterned(fn_info.return_type));
                    debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, .void));
                    debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, ptr_ty));
                } else {
                    const ret_ty: Type = .fromInterned(fn_info.return_type);
                    debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, ret_ty));
                }

                if (fn_info.cc == .auto and zcu.comp.config.any_error_tracing) {
                    // Stack trace pointer.
                    debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, .ptr_usize));
                }

                for (fn_info.param_types.get(ip)) |param_ty_ip| {
                    const param_ty: Type = .fromInterned(param_ty_ip);
                    if (!param_ty.hasRuntimeBits(zcu)) continue;
                    if (isByRef(param_ty, zcu)) {
                        const ptr_ty = try pt.singleConstPtrType(param_ty);
                        debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, ptr_ty));
                    } else {
                        debug_param_types.appendAssumeCapacity(try o.getDebugType(pt, param_ty));
                    }
                }

                return o.builder.debugSubroutineType(
                    try o.builder.metadataTuple(debug_param_types.items),
                );
            },
            .@"struct" => {
                if (ty.isTuple(zcu)) {
                    const tuple = ip.indexToKey(ty.toIntern()).tuple_type;
                    var fields: std.ArrayList(Builder.Metadata) = .empty;
                    defer fields.deinit(gpa);

                    try fields.ensureUnusedCapacity(gpa, tuple.types.len);

                    comptime assert(struct_layout_version == 2);
                    var offset: u64 = 0;

                    for (tuple.types.get(ip), tuple.values.get(ip), 0..) |field_ty_ip, field_val, i| {
                        const field_ty: Type = .fromInterned(field_ty_ip);
                        if (field_val != .none or !field_ty.hasRuntimeBits(zcu)) continue;

                        const field_size = field_ty.abiSize(zcu);
                        const field_align = field_ty.abiAlignment(zcu);
                        const field_offset = field_align.forward(offset);
                        offset = field_offset + field_size;

                        fields.appendAssumeCapacity(try o.builder.debugMemberType(
                            try o.builder.metadataStringFmt("{d}", .{i}),
                            null, // file
                            ty_fwd_ref,
                            0, // line
                            try o.getDebugType(pt, field_ty),
                            field_size * 8,
                            field_align.toByteUnits().? * 8,
                            field_offset * 8,
                        ));
                    }

                    return o.builder.debugStructType(
                        name,
                        null, // file
                        o.debug_compile_unit.unwrap().?,
                        0, // line
                        null, // underlying type
                        ty.abiSize(zcu) * 8,
                        (ty.abiAlignment(zcu).toByteUnits() orelse 0) * 8,
                        try o.builder.metadataTuple(fields.items),
                    );
                }

                const struct_type = zcu.typeToStruct(ty).?;

                const file = try o.getDebugFile(struct_type.zir_index.resolveFile(ip));
                const scope = if (ty.getParentNamespace(zcu).unwrap()) |parent_namespace|
                    try o.namespaceToDebugScope(pt, parent_namespace)
                else
                    file;

                const line = ty.typeDeclSrcLine(zcu).? + 1;

                var fields: std.ArrayList(Builder.Metadata) = .empty;
                defer fields.deinit(gpa);

                switch (struct_type.layout) {
                    .@"packed" => {
                        try fields.ensureTotalCapacityPrecise(gpa, 1);
                        fields.appendAssumeCapacity(try o.builder.debugMemberType(
                            try o.builder.metadataString("bits"),
                            null, // file
                            ty_fwd_ref,
                            0, // line
                            try o.getDebugType(pt, .fromInterned(struct_type.packed_backing_int_type)),
                            ty.abiSize(zcu) * 8,
                            ty.abiAlignment(zcu).toByteUnits().? * 8,
                            0, // offset
                        ));
                    },
                    .auto, .@"extern" => {
                        comptime assert(struct_layout_version == 2);
                        try fields.ensureTotalCapacityPrecise(gpa, struct_type.field_types.len);
                        var it = struct_type.iterateRuntimeOrder(ip);
                        while (it.next()) |field_index| {
                            const field_ty: Type = .fromInterned(struct_type.field_types.get(ip)[field_index]);
                            if (!field_ty.hasRuntimeBits(zcu)) continue;
                            const field_size = field_ty.abiSize(zcu);
                            const field_align = switch (ty.explicitFieldAlignment(field_index, zcu)) {
                                .none => field_ty.abiAlignment(zcu),
                                else => |a| a,
                            };
                            const field_offset = struct_type.field_offsets.get(ip)[field_index];
                            const field_name = struct_type.field_names.get(ip)[field_index];
                            fields.appendAssumeCapacity(try o.builder.debugMemberType(
                                try o.builder.metadataString(field_name.toSlice(ip)),
                                null, // file
                                ty_fwd_ref,
                                0, // line
                                try o.getDebugType(pt, field_ty),
                                field_size * 8,
                                field_align.toByteUnits().? * 8,
                                field_offset * 8,
                            ));
                        }
                    },
                }

                return o.builder.debugStructType(
                    name,
                    file,
                    scope,
                    line,
                    null, // underlying type
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(fields.items),
                );
            },
            .@"union" => {
                const union_type = ip.loadUnionType(ty.toIntern());

                const file = try o.getDebugFile(union_type.zir_index.resolveFile(ip));
                const scope = if (ty.getParentNamespace(zcu).unwrap()) |parent_namespace|
                    try o.namespaceToDebugScope(pt, parent_namespace)
                else
                    file;

                const line = ty.typeDeclSrcLine(zcu).? + 1;

                const enum_tag_ty: Type = .fromInterned(union_type.enum_tag_type);

                if (union_type.layout == .@"packed") {
                    const bitpack_field = try o.builder.debugMemberType(
                        try o.builder.metadataString("bits"),
                        null, // file
                        ty_fwd_ref,
                        0, // line
                        try o.getDebugType(pt, .fromInterned(union_type.packed_backing_int_type)),
                        ty.abiSize(zcu) * 8,
                        ty.abiAlignment(zcu).toByteUnits().? * 8,
                        0, // offset
                    );
                    return o.builder.debugStructType(
                        name,
                        file,
                        scope,
                        line,
                        null, // underlying type
                        ty.abiSize(zcu) * 8,
                        ty.abiAlignment(zcu).toByteUnits().? * 8,
                        try o.builder.metadataTuple(&.{bitpack_field}),
                    );
                }

                const layout = Type.getUnionLayout(union_type, zcu);

                if (layout.payload_size == 0) {
                    const fields_tuple: ?Builder.Metadata = fields: {
                        if (layout.tag_size == 0) break :fields null;
                        break :fields try o.builder.metadataTuple(&.{
                            try o.builder.debugMemberType(
                                try o.builder.metadataString("tag"),
                                null, // file
                                ty_fwd_ref,
                                0, // line
                                try o.getDebugType(pt, enum_tag_ty),
                                layout.tag_size * 8,
                                layout.tag_align.toByteUnits().? * 8,
                                0, // offset
                            ),
                        });
                    };
                    return o.builder.debugStructType(
                        name,
                        file,
                        scope,
                        line,
                        null, // underlying type
                        ty.abiSize(zcu) * 8,
                        ty.abiAlignment(zcu).toByteUnits().? * 8,
                        fields_tuple,
                    );
                }

                var fields: std.ArrayList(Builder.Metadata) = try .initCapacity(gpa, union_type.field_types.len);
                defer fields.deinit(gpa);

                const payload_fwd_ref = if (layout.tag_size == 0)
                    ty_fwd_ref
                else
                    try o.builder.debugForwardReference();

                for (0..union_type.field_types.len) |field_index| {
                    const field_ty = union_type.field_types.get(ip)[field_index];

                    const field_size = Type.fromInterned(field_ty).abiSize(zcu);
                    const field_align: InternPool.Alignment = ty.explicitFieldAlignment(field_index, zcu);

                    const field_name = enum_tag_ty.enumFieldName(field_index, zcu);
                    fields.appendAssumeCapacity(try o.builder.debugMemberType(
                        try o.builder.metadataString(field_name.toSlice(ip)),
                        null, // file
                        payload_fwd_ref,
                        0, // line
                        try o.getDebugType(pt, .fromInterned(field_ty)),
                        field_size * 8,
                        (field_align.toByteUnits() orelse 0) * 8,
                        0, // offset
                    ));
                }

                const debug_payload_type = try o.builder.debugUnionType(
                    payload_name: {
                        if (layout.tag_size == 0) break :payload_name name;
                        break :payload_name try o.builder.metadataStringFmt("{f}:Payload", .{ty.fmt(pt)});
                    },
                    file,
                    scope,
                    line,
                    null, // underlying type
                    layout.payload_size * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(fields.items),
                );

                if (layout.tag_size == 0) {
                    return debug_payload_type;
                }

                o.builder.resolveDebugForwardReference(payload_fwd_ref, debug_payload_type);

                const tag_offset: u64, const payload_offset: u64 = offsets: {
                    if (layout.tag_align.compare(.gte, layout.payload_align)) {
                        break :offsets .{ 0, layout.payload_align.forward(layout.tag_size) };
                    } else {
                        break :offsets .{ layout.tag_align.forward(layout.payload_size), 0 };
                    }
                };

                const tag_member_type = try o.builder.debugMemberType(
                    try o.builder.metadataString("tag"),
                    null, // file
                    ty_fwd_ref,
                    0, // line
                    try o.getDebugType(pt, enum_tag_ty),
                    layout.tag_size * 8,
                    layout.tag_align.toByteUnits().? * 8,
                    tag_offset * 8,
                );

                const payload_member_type = try o.builder.debugMemberType(
                    try o.builder.metadataString("payload"),
                    null, // file
                    ty_fwd_ref,
                    0, // line
                    debug_payload_type,
                    layout.payload_size * 8,
                    layout.payload_align.toByteUnits().? * 8,
                    payload_offset * 8,
                );

                const full_fields: [2]Builder.Metadata =
                    if (layout.tag_align.compare(.gte, layout.payload_align))
                        .{ tag_member_type, payload_member_type }
                    else
                        .{ payload_member_type, tag_member_type };

                return o.builder.debugStructType(
                    name,
                    file,
                    scope,
                    line,
                    null, // underlying type
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(&full_fields),
                );
            },
            .@"enum" => {
                const file = try o.getDebugFile(ty.typeDeclInstAllowGeneratedTag(zcu).?.resolveFile(ip));
                const scope = if (ty.getParentNamespace(zcu).unwrap()) |parent_namespace|
                    try o.namespaceToDebugScope(pt, parent_namespace)
                else
                    file;

                const line = ty.typeDeclSrcLine(zcu).? + 1;

                if (!ty.hasRuntimeBits(zcu)) {
                    return o.builder.debugStructType(
                        name,
                        file,
                        scope,
                        line,
                        null, // underlying type
                        ty.abiSize(zcu) * 8,
                        ty.abiAlignment(zcu).toByteUnits().? * 8,
                        null, // fields
                    );
                }

                const enum_type = ip.loadEnumType(ty.toIntern());
                const enumerators = try gpa.alloc(Builder.Metadata, enum_type.field_names.len);
                defer gpa.free(enumerators);

                const int_ty: Type = .fromInterned(enum_type.int_tag_type);
                const int_info = ty.intInfo(zcu);
                assert(int_info.bits != 0);

                for (enumerators, enum_type.field_names.get(ip), 0..) |*out, field_name, field_index| {
                    var space: Value.BigIntSpace = undefined;
                    const field_val: std.math.big.int.Const = switch (enum_type.field_values.len) {
                        0 => std.math.big.int.Mutable.init(&space.limbs, field_index).toConst(),
                        else => Value.fromInterned(enum_type.field_values.get(ip)[field_index]).toBigInt(&space, zcu),
                    };
                    out.* = try o.builder.debugEnumerator(
                        try o.builder.metadataString(field_name.toSlice(ip)),
                        int_info.signedness == .unsigned,
                        int_info.bits,
                        field_val,
                    );
                }

                const debug_enum_type = try o.builder.debugEnumerationType(
                    name,
                    file,
                    scope,
                    line,
                    try o.getDebugType(pt, int_ty),
                    ty.abiSize(zcu) * 8,
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    try o.builder.metadataTuple(enumerators),
                );
                try o.debug_enums.append(gpa, debug_enum_type);
                return debug_enum_type;
            },
            .@"opaque" => {
                if (ty.toIntern() == .anyopaque_type) {
                    return o.builder.debugSignedType(name, 0);
                }

                const file = try o.getDebugFile(ty.typeDeclInstAllowGeneratedTag(zcu).?.resolveFile(ip));
                const scope = if (ty.getParentNamespace(zcu).unwrap()) |parent_namespace|
                    try o.namespaceToDebugScope(pt, parent_namespace)
                else
                    file;

                const line = ty.typeDeclSrcLine(zcu).? + 1;

                return o.builder.debugStructType(
                    name,
                    file,
                    scope,
                    line,
                    null, // underlying type
                    0, // size
                    ty.abiAlignment(zcu).toByteUnits().? * 8,
                    null, // fields
                );
            },
            .frame => @panic("TODO implement lowerDebugType for Frame types"),
            .@"anyframe" => @panic("TODO implement lowerDebugType for AnyFrame types"),
        }
    }

    /// Called in `emit` so that the global error set is fully populated.
    fn lowerDebugAnyerrorType(o: *Object) Allocator.Error!Builder.Metadata {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const gpa = zcu.comp.gpa;

        const error_set_bits = zcu.errorSetBits();
        const error_names = ip.global_error_set.getNamesFromMainThread();

        const enumerators = try gpa.alloc(Builder.Metadata, error_names.len + 1);
        defer gpa.free(enumerators);

        // The value 0 means "no error" in optionals and error unions.
        enumerators[0] = try o.builder.debugEnumerator(
            try o.builder.metadataString("null"),
            true, // unsigned,
            error_set_bits,
            .{ .limbs = &.{0}, .positive = true }, // zero
        );

        for (enumerators[1..], error_names, 1..) |*out, error_name, error_value| {
            var space: Value.BigIntSpace = undefined;
            var bigint: std.math.big.int.Mutable = .init(&space.limbs, error_value);
            out.* = try o.builder.debugEnumerator(
                try o.builder.metadataStringFmt("error.{f}", .{error_name.fmtId(ip)}),
                true, // unsigned
                error_set_bits,
                bigint.toConst(),
            );
        }

        const debug_enum_type = try o.builder.debugEnumerationType(
            try o.builder.metadataString("anyerror"),
            null, // file
            o.debug_compile_unit.unwrap().?, // scope
            0, // line
            try o.builder.debugUnsignedType(null, error_set_bits),
            Type.anyerror.abiSize(zcu) * 8,
            Type.anyerror.abiAlignment(zcu).toByteUnits().? * 8,
            try o.builder.metadataTuple(enumerators),
        );
        try o.debug_enums.append(gpa, debug_enum_type);
        return debug_enum_type;
    }

    fn namespaceToDebugScope(o: *Object, pt: Zcu.PerThread, namespace_index: InternPool.NamespaceIndex) !Builder.Metadata {
        const zcu = o.zcu;
        const namespace = zcu.namespacePtr(namespace_index);
        if (namespace.parent == .none) return try o.getDebugFile(namespace.file_scope);
        return o.getDebugType(pt, .fromInterned(namespace.owner_type));
    }

    /// Sets the attributes and callconv of the given `Builder.Function`, which corresponds to the
    /// given `Nav` (which is a function).
    fn addLlvmFunctionAttributes(
        o: *Object,
        pt: Zcu.PerThread,
        nav_id: InternPool.Nav.Index,
        function_index: Builder.Function.Index,
    ) Allocator.Error!void {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const nav = ip.getNav(nav_id);
        const owner_mod = zcu.navFileScope(nav_id).mod.?;
        const ty: Type = .fromInterned(nav.resolved.?.type);

        const fn_info = zcu.typeToFunc(ty).?;
        const target = &owner_mod.resolved_target.result;

        var attributes: Builder.FunctionAttributes.Wip = .{};
        defer attributes.deinit(&o.builder);

        if (target.cpu.arch.isWasm()) if (nav.getExtern(ip)) |@"extern"| {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("wasm-import-name"),
                .value = try o.builder.string(nav.name.toSlice(ip)),
            } }, &o.builder);
            if (@"extern".lib_name.toSlice(ip)) |lib_name_slice| {
                if (!std.mem.eql(u8, lib_name_slice, "c")) try attributes.addFnAttr(.{ .string = .{
                    .kind = try o.builder.string("wasm-import-module"),
                    .value = try o.builder.string(lib_name_slice),
                } }, &o.builder);
            }
        };

        if (fn_info.cc == .async) {
            @panic("TODO: LLVM backend lower async function");
        }

        {
            const cc_info = toLlvmCallConv(fn_info.cc, target).?;

            function_index.setCallConv(cc_info.llvm_cc, &o.builder);

            if (cc_info.align_stack) {
                try attributes.addFnAttr(.{ .alignstack = .wrap(.fromByteUnits(target.stackAlignment())) }, &o.builder);
            } else {
                _ = try attributes.removeFnAttr(.alignstack);
            }

            if (cc_info.naked) {
                try attributes.addFnAttr(.naked, &o.builder);
            } else {
                _ = try attributes.removeFnAttr(.naked);
            }

            for (0..cc_info.inreg_param_count) |param_idx| {
                try attributes.addParamAttr(param_idx, .inreg, &o.builder);
            }
            for (cc_info.inreg_param_count..std.math.maxInt(u2)) |param_idx| {
                _ = try attributes.removeParamAttr(param_idx, .inreg);
            }

            switch (fn_info.cc) {
                inline .riscv64_interrupt,
                .riscv32_interrupt,
                .mips_interrupt,
                .mips64_interrupt,
                => |info| {
                    try attributes.addFnAttr(.{ .string = .{
                        .kind = try o.builder.string("interrupt"),
                        .value = try o.builder.string(@tagName(info.mode)),
                    } }, &o.builder);
                },
                .arm_interrupt,
                => |info| {
                    try attributes.addFnAttr(.{ .string = .{
                        .kind = try o.builder.string("interrupt"),
                        .value = try o.builder.string(switch (info.type) {
                            .generic => "",
                            .irq => "IRQ",
                            .fiq => "FIQ",
                            .swi => "SWI",
                            .abort => "ABORT",
                            .undef => "UNDEF",
                        }),
                    } }, &o.builder);
                },
                // these function attributes serve as a backup against any mistakes LLVM makes.
                // clang sets both the function's calling convention and the function attributes
                // in its backend, so future patches to the AVR backend could end up checking only one,
                // possibly breaking our support. it's safer to just emit both.
                .avr_interrupt, .avr_signal, .csky_interrupt => {
                    try attributes.addFnAttr(.{ .string = .{
                        .kind = try o.builder.string(switch (fn_info.cc) {
                            .avr_interrupt,
                            .csky_interrupt,
                            => "interrupt",
                            .avr_signal => "signal",
                            else => unreachable,
                        }),
                        .value = .empty,
                    } }, &o.builder);
                },
                else => {},
            }
        }

        // Function attributes that are independent of analysis results of the function body.
        try o.addCommonFnAttributes(
            &attributes,
            owner_mod,
            // Some backends don't respect the `naked` attribute in `TargetFrameLowering::hasFP()`,
            // so for these backends, LLVM will happily emit code that accesses the stack through
            // the frame pointer. This is nonsensical since what the `naked` attribute does is
            // suppress generation of the prologue and epilogue, and the prologue is where the
            // frame pointer normally gets set up. At time of writing, this is the case for at
            // least x86 and RISC-V.
            owner_mod.omit_frame_pointer or fn_info.cc == .naked,
        );

        if (fn_info.return_type == .noreturn_type) try attributes.addFnAttr(.noreturn, &o.builder);

        var it = iterateParamTypes(o, fn_info);
        if (firstParamSRet(fn_info, zcu, target)) {
            // Sret pointers must not be address 0
            try attributes.addParamAttr(it.llvm_index, .nonnull, &o.builder);
            try attributes.addParamAttr(it.llvm_index, .@"noalias", &o.builder);

            const raw_llvm_ret_ty = try o.lowerType(.fromInterned(fn_info.return_type));
            try attributes.addParamAttr(it.llvm_index, .{ .sret = raw_llvm_ret_ty }, &o.builder);
            it.llvm_index += 1;
        } else if (ccAbiPromoteInt(fn_info.cc, zcu, Type.fromInterned(fn_info.return_type))) |s| switch (s) {
            .signed => try attributes.addRetAttr(.signext, &o.builder),
            .unsigned => try attributes.addRetAttr(.zeroext, &o.builder),
        };

        const err_return_tracing = fn_info.cc == .auto and zcu.comp.config.any_error_tracing;
        if (err_return_tracing) {
            try attributes.addParamAttr(it.llvm_index, .nonnull, &o.builder);
            it.llvm_index += 1;
        }
        while (try it.next()) |lowering| switch (lowering) {
            .byval => {
                const param_index = it.zig_index - 1;
                const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[param_index]);
                if (!isByRef(param_ty, zcu)) {
                    try o.addByValParamAttrs(pt, &attributes, param_ty, param_index, fn_info, it.llvm_index - 1);
                }
            },
            .byref => {
                const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                const param_llvm_ty = try o.lowerType(param_ty);
                const alignment = param_ty.abiAlignment(zcu);
                try o.addByRefParamAttrs(&attributes, it.llvm_index - 1, alignment.toLlvm(), it.byval_attr, param_llvm_ty);
            },
            .byref_mut => try attributes.addParamAttr(it.llvm_index - 1, .noundef, &o.builder),
            .slice => {
                const param_ty: Type = .fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                const ptr_info = param_ty.ptrInfo(zcu);
                const llvm_ptr_index = it.llvm_index - 2;
                if (std.math.cast(u5, it.zig_index - 1)) |i| {
                    if (@as(u1, @truncate(fn_info.noalias_bits >> i)) != 0) {
                        try attributes.addParamAttr(llvm_ptr_index, .@"noalias", &o.builder);
                    }
                }
                if (param_ty.zigTypeTag(zcu) != .optional and
                    !ptr_info.flags.is_allowzero and
                    ptr_info.flags.address_space == .generic)
                {
                    try attributes.addParamAttr(llvm_ptr_index, .nonnull, &o.builder);
                }
                if (ptr_info.flags.is_const) {
                    try attributes.addParamAttr(llvm_ptr_index, .readonly, &o.builder);
                }
                const elem_align: Builder.Alignment.Lazy = switch (ptr_info.flags.alignment) {
                    else => |a| .wrap(a.toLlvm()),
                    .none => try o.lazyAbiAlignment(pt, .fromInterned(ptr_info.child)),
                };
                try attributes.addParamAttr(llvm_ptr_index, .{ .@"align" = elem_align }, &o.builder);
            },
            // No attributes needed for these.
            .no_bits,
            .abi_sized_int,
            .multiple_llvm_types,
            .float_array,
            .i32_array,
            .i64_array,
            => continue,
        };

        function_index.setAttributes(try attributes.finish(&o.builder), &o.builder);
    }

    fn addCommonFnAttributes(
        o: *Object,
        attributes: *Builder.FunctionAttributes.Wip,
        owner_mod: *Package.Module,
        omit_frame_pointer: bool,
    ) Allocator.Error!void {
        if (!owner_mod.red_zone) {
            try attributes.addFnAttr(.noredzone, &o.builder);
        }
        if (omit_frame_pointer) {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("frame-pointer"),
                .value = try o.builder.string("none"),
            } }, &o.builder);
        } else {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("frame-pointer"),
                .value = try o.builder.string("all"),
            } }, &o.builder);
        }
        try attributes.addFnAttr(.nounwind, &o.builder);
        if (owner_mod.unwind_tables != .none) {
            try attributes.addFnAttr(
                .{ .uwtable = if (owner_mod.unwind_tables == .async) .async else .sync },
                &o.builder,
            );
        }
        if (owner_mod.optimize_mode == .ReleaseSmall) {
            try attributes.addFnAttr(.minsize, &o.builder);
            try attributes.addFnAttr(.optsize, &o.builder);
        }
        const target = &owner_mod.resolved_target.result;
        if (target.cpu.model.llvm_name) |s| {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("target-cpu"),
                .value = try o.builder.string(s),
            } }, &o.builder);
        }
        if (owner_mod.resolved_target.llvm_cpu_features) |s| {
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("target-features"),
                .value = try o.builder.string(std.mem.span(s)),
            } }, &o.builder);
        }
        if (target.abi.float() == .soft) {
            // `use-soft-float` means "use software routines for floating point computations". In
            // other words, it configures how LLVM lowers basic float instructions like `fcmp`,
            // `fadd`, etc. The float calling convention is configured on `TargetMachine` and is
            // mostly an orthogonal concept, although obviously we do need hardware float operations
            // to actually be able to pass float values in float registers.
            //
            // Ideally, we would support something akin to the `-mfloat-abi=softfp` option that GCC
            // and Clang support for Arm32 and CSKY. We don't currently expose such an option in
            // Zig, and using CPU features as the source of truth for this makes for a miserable
            // user experience since people expect e.g. `arm-linux-gnueabi` to mean full soft float
            // unless the compiler has explicitly been told otherwise. (And note that our baseline
            // CPU models almost all include FPU features!)
            //
            // Revisit this at some point.
            try attributes.addFnAttr(.{ .string = .{
                .kind = try o.builder.string("use-soft-float"),
                .value = try o.builder.string("true"),
            } }, &o.builder);

            // This prevents LLVM from using FPU/SIMD code for things like `memcpy`. As for the
            // above, this should be revisited if `softfp` support is added.
            try attributes.addFnAttr(.noimplicitfloat, &o.builder);
        }
    }

    pub fn errorIntType(o: *Object) Allocator.Error!Builder.Type {
        return o.builder.intType(o.zcu.errorSetBits());
    }

    pub fn lowerType(o: *Object, t: Type) Allocator.Error!Builder.Type {
        const zcu = o.zcu;
        const target = zcu.getTarget();
        const ip = &zcu.intern_pool;
        return switch (t.toIntern()) {
            .u0_type, .i0_type => unreachable, // no runtime bits
            inline .u1_type,
            .u8_type,
            .i8_type,
            .u16_type,
            .i16_type,
            .u29_type,
            .u32_type,
            .i32_type,
            .u64_type,
            .i64_type,
            .u80_type,
            .u128_type,
            .i128_type,
            => |tag| @field(Builder.Type, "i" ++ @tagName(tag)[1 .. @tagName(tag).len - "_type".len]),
            .usize_type, .isize_type => try o.builder.intType(target.ptrBitWidth()),
            inline .c_char_type,
            .c_short_type,
            .c_ushort_type,
            .c_int_type,
            .c_uint_type,
            .c_long_type,
            .c_ulong_type,
            .c_longlong_type,
            .c_ulonglong_type,
            => |tag| try o.builder.intType(target.cTypeBitSize(
                @field(std.Target.CType, @tagName(tag)["c_".len .. @tagName(tag).len - "_type".len]),
            )),
            .c_longdouble_type,
            .f16_type,
            .f32_type,
            .f64_type,
            .f80_type,
            .f128_type,
            => switch (t.floatBits(target)) {
                16 => if (backendSupportsF16(target)) .half else .i16,
                32 => .float,
                64 => .double,
                80 => if (backendSupportsF80(target)) .x86_fp80 else .i80,
                128 => .fp128,
                else => unreachable,
            },
            .anyopaque_type => {
                // This is unreachable except when used as the type for an extern global.
                // For example: `@extern(*anyopaque, .{ .name = "foo"})` should produce
                // @foo = external global i8
                return .i8;
            },
            .bool_type => .i1,
            .anyerror_type => try o.errorIntType(),
            .void_type => unreachable, // no runtime bits
            .type_type => unreachable, // no runtime bits
            .comptime_int_type => unreachable, // no runtime bits
            .comptime_float_type => unreachable, // no runtime bits
            .noreturn_type => unreachable, // no runtime bits
            .null_type => unreachable, // no runtime bits
            .undefined_type => unreachable, // no runtime bits
            .enum_literal_type => unreachable, // no runtime bits
            .optional_noreturn_type => unreachable, // no runtime bits
            .empty_tuple_type => unreachable, // no runtime bits
            .anyframe_type => @panic("TODO implement lowerType for AnyFrame types"),
            .ptr_usize_type,
            .ptr_const_comptime_int_type,
            .manyptr_u8_type,
            .manyptr_const_u8_type,
            .manyptr_const_u8_sentinel_0_type,
            => .ptr,
            .slice_const_u8_type,
            .slice_const_u8_sentinel_0_type,
            => try o.builder.structType(.normal, &.{ .ptr, try o.lowerType(.usize) }),
            .anyerror_void_error_union_type,
            .adhoc_inferred_error_set_type,
            => try o.errorIntType(),
            .generic_poison_type => unreachable,
            // values, not types
            .undef,
            .undef_bool,
            .undef_usize,
            .undef_u1,
            .zero,
            .zero_usize,
            .zero_u1,
            .zero_u8,
            .one,
            .one_usize,
            .one_u1,
            .one_u8,
            .four_u8,
            .negative_one,
            .void_value,
            .unreachable_value,
            .null_value,
            .bool_true,
            .bool_false,
            .empty_tuple,
            .none,
            => unreachable,
            else => switch (ip.indexToKey(t.toIntern())) {
                .int_type => |int_type| try o.builder.intType(int_type.bits),
                .ptr_type => |ptr_type| type: {
                    const ptr_ty = try o.builder.ptrType(
                        toLlvmAddressSpace(ptr_type.flags.address_space, target),
                    );
                    break :type switch (ptr_type.flags.size) {
                        .one, .many, .c => ptr_ty,
                        .slice => try o.builder.structType(.normal, &.{
                            ptr_ty,
                            try o.lowerType(.usize),
                        }),
                    };
                },
                .array_type => |array_type| o.builder.arrayType(
                    array_type.lenIncludingSentinel(),
                    try o.lowerType(.fromInterned(array_type.child)),
                ),
                .vector_type => |vector_type| o.builder.vectorType(
                    .normal,
                    vector_type.len,
                    try o.lowerType(.fromInterned(vector_type.child)),
                ),
                .opt_type => |child_ty| {
                    // Must stay in sync with `opt_payload` logic in `lowerPtr`.
                    switch (Type.fromInterned(child_ty).classify(zcu)) {
                        .no_possible_value, .fully_comptime => unreachable,
                        .one_possible_value => return .i8,
                        .runtime, .partially_comptime => {},
                    }

                    const payload_ty = try o.lowerType(.fromInterned(child_ty));
                    if (t.optionalReprIsPayload(zcu)) return payload_ty;

                    comptime assert(optional_layout_version == 3);
                    var fields: [3]Builder.Type = .{ payload_ty, .i8, undefined };
                    var fields_len: usize = 2;
                    const offset = Type.fromInterned(child_ty).abiSize(zcu) + 1;
                    const abi_size = t.abiSize(zcu);
                    const padding_len = abi_size - offset;
                    if (padding_len > 0) {
                        fields[2] = try o.builder.arrayType(padding_len, .i8);
                        fields_len = 3;
                    }
                    return o.builder.structType(.normal, fields[0..fields_len]);
                },
                .anyframe_type => @panic("TODO implement lowerType for AnyFrame types"),
                .error_union_type => |error_union_type| {
                    // Must stay in sync with `codegen.errUnionPayloadOffset`.
                    // See logic in `lowerPtr`.
                    const error_type = try o.errorIntType();

                    switch (Type.fromInterned(error_union_type.payload_type).classify(zcu)) {
                        .fully_comptime => unreachable,
                        .no_possible_value, .one_possible_value => return error_type,
                        .runtime, .partially_comptime => {},
                    }

                    const payload_type = try o.lowerType(.fromInterned(error_union_type.payload_type));

                    const payload_align = Type.fromInterned(error_union_type.payload_type).abiAlignment(zcu);
                    const error_align: InternPool.Alignment = .fromByteUnits(std.zig.target.intAlignment(target, zcu.errorSetBits()));

                    const payload_size = Type.fromInterned(error_union_type.payload_type).abiSize(zcu);
                    const error_size = std.zig.target.intByteSize(target, zcu.errorSetBits());

                    var fields: [3]Builder.Type = undefined;
                    var fields_len: usize = 2;
                    const padding_len = if (error_align.compare(.gt, payload_align)) pad: {
                        fields[0] = error_type;
                        fields[1] = payload_type;
                        const payload_end =
                            payload_align.forward(error_size) +
                            payload_size;
                        const abi_size = error_align.forward(payload_end);
                        break :pad abi_size - payload_end;
                    } else pad: {
                        fields[0] = payload_type;
                        fields[1] = error_type;
                        const error_end =
                            error_align.forward(payload_size) +
                            error_size;
                        const abi_size = payload_align.forward(error_end);
                        break :pad abi_size - error_end;
                    };
                    if (padding_len > 0) {
                        fields[2] = try o.builder.arrayType(padding_len, .i8);
                        fields_len = 3;
                    }
                    return o.builder.structType(.normal, fields[0..fields_len]);
                },
                .simple_type => unreachable,
                .struct_type => {
                    if (o.type_map.get(t.toIntern())) |value| return value;

                    const struct_type = ip.loadStructType(t.toIntern());

                    if (struct_type.layout == .@"packed") {
                        const int_ty = try o.lowerType(.fromInterned(struct_type.packed_backing_int_type));
                        try o.type_map.put(o.gpa, t.toIntern(), int_ty);
                        return int_ty;
                    }

                    assert(struct_type.size > 0);

                    var llvm_field_types: std.ArrayList(Builder.Type) = .empty;
                    defer llvm_field_types.deinit(o.gpa);
                    // Although we can estimate how much capacity to add, these cannot be
                    // relied upon because of the recursive calls to lowerType below.
                    try llvm_field_types.ensureUnusedCapacity(o.gpa, struct_type.field_types.len);

                    comptime assert(struct_layout_version == 2);
                    var offset: u64 = 0;
                    var struct_kind: Builder.Type.Structure.Kind = .normal;
                    // When we encounter a zero-bit field, we place it here so we know to map it to the next non-zero-bit field (if any).
                    var it = struct_type.iterateRuntimeOrder(ip);
                    var max_field_ty_align: InternPool.Alignment = .@"1";
                    while (it.next()) |field_index| {
                        const field_ty = Type.fromInterned(struct_type.field_types.get(ip)[field_index]);
                        const field_ty_align = field_ty.abiAlignment(zcu);
                        max_field_ty_align = max_field_ty_align.maxStrict(field_ty_align);

                        const prev_offset = offset;
                        offset = struct_type.field_offsets.get(ip)[field_index];
                        if (@ctz(offset) < field_ty_align.toLog2Units()) {
                            struct_kind = .@"packed"; // prevent unexpected padding before this field
                        }

                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) try llvm_field_types.append(
                            o.gpa,
                            try o.builder.arrayType(padding_len, .i8),
                        );

                        if (!field_ty.hasRuntimeBits(zcu)) continue;

                        try llvm_field_types.append(o.gpa, try o.lowerType(field_ty));

                        offset += field_ty.abiSize(zcu);
                    }
                    {
                        const prev_offset = offset;
                        offset = struct_type.alignment.forward(offset);
                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) try llvm_field_types.append(
                            o.gpa,
                            try o.builder.arrayType(padding_len, .i8),
                        );
                        if (@ctz(offset) < max_field_ty_align.toLog2Units()) {
                            struct_kind = .@"packed"; // prevent unexpected trailing padding
                        }
                    }

                    const ty = try o.builder.opaqueType(try o.builder.string(t.containerTypeName(ip).toSlice(ip)));
                    try o.type_map.put(o.gpa, t.toIntern(), ty);

                    o.builder.namedTypeSetBody(
                        ty,
                        try o.builder.structType(struct_kind, llvm_field_types.items),
                    );
                    return ty;
                },
                .tuple_type => |tuple_type| {
                    var llvm_field_types: std.ArrayList(Builder.Type) = .empty;
                    defer llvm_field_types.deinit(o.gpa);
                    // Although we can estimate how much capacity to add, these cannot be
                    // relied upon because of the recursive calls to lowerType below.
                    try llvm_field_types.ensureUnusedCapacity(o.gpa, tuple_type.types.len);

                    comptime assert(struct_layout_version == 2);
                    var offset: u64 = 0;
                    var big_align: InternPool.Alignment = .@"1";

                    for (
                        tuple_type.types.get(ip),
                        tuple_type.values.get(ip),
                    ) |field_ty, field_val| {
                        if (field_val != .none) continue;

                        const field_align = Type.fromInterned(field_ty).abiAlignment(zcu);
                        big_align = big_align.max(field_align);
                        const prev_offset = offset;
                        offset = field_align.forward(offset);

                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) try llvm_field_types.append(
                            o.gpa,
                            try o.builder.arrayType(padding_len, .i8),
                        );
                        if (!Type.fromInterned(field_ty).hasRuntimeBits(zcu)) {
                            continue;
                        }
                        try llvm_field_types.append(o.gpa, try o.lowerType(.fromInterned(field_ty)));

                        offset += Type.fromInterned(field_ty).abiSize(zcu);
                    }
                    {
                        const prev_offset = offset;
                        offset = big_align.forward(offset);
                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) try llvm_field_types.append(
                            o.gpa,
                            try o.builder.arrayType(padding_len, .i8),
                        );
                    }
                    assert(offset > 0);
                    return o.builder.structType(.normal, llvm_field_types.items);
                },
                .union_type => {
                    if (o.type_map.get(t.toIntern())) |value| return value;

                    const union_obj = ip.loadUnionType(t.toIntern());

                    if (union_obj.layout == .@"packed") {
                        const int_ty = try o.lowerType(.fromInterned(union_obj.packed_backing_int_type));
                        try o.type_map.put(o.gpa, t.toIntern(), int_ty);
                        return int_ty;
                    }

                    assert(union_obj.size > 0);

                    const layout = Type.getUnionLayout(union_obj, zcu);

                    if (layout.payload_size == 0) {
                        const enum_tag_ty = try o.lowerType(.fromInterned(union_obj.enum_tag_type));
                        try o.type_map.put(o.gpa, t.toIntern(), enum_tag_ty);
                        return enum_tag_ty;
                    }

                    const aligned_field_ty = Type.fromInterned(union_obj.field_types.get(ip)[layout.most_aligned_field]);
                    const aligned_field_llvm_ty = try o.lowerType(aligned_field_ty);

                    const payload_ty = ty: {
                        if (layout.most_aligned_field_size == layout.payload_size) {
                            break :ty aligned_field_llvm_ty;
                        }
                        const padding_len = if (layout.tag_size == 0)
                            layout.abi_size - layout.most_aligned_field_size
                        else
                            layout.payload_size - layout.most_aligned_field_size;
                        break :ty try o.builder.structType(.@"packed", &.{
                            aligned_field_llvm_ty,
                            try o.builder.arrayType(padding_len, .i8),
                        });
                    };

                    if (layout.tag_size == 0) {
                        const ty = try o.builder.opaqueType(try o.builder.string(t.containerTypeName(ip).toSlice(ip)));
                        try o.type_map.put(o.gpa, t.toIntern(), ty);

                        o.builder.namedTypeSetBody(
                            ty,
                            try o.builder.structType(.normal, &.{payload_ty}),
                        );
                        return ty;
                    }
                    const enum_tag_ty = try o.lowerType(.fromInterned(union_obj.enum_tag_type));

                    // Put the tag before or after the payload depending on which one's
                    // alignment is greater.
                    var llvm_fields: [3]Builder.Type = undefined;
                    var llvm_fields_len: usize = 2;

                    if (layout.tag_align.compare(.gte, layout.payload_align)) {
                        llvm_fields = .{ enum_tag_ty, payload_ty, .none };
                    } else {
                        llvm_fields = .{ payload_ty, enum_tag_ty, .none };
                    }

                    // Insert padding to make the LLVM struct ABI size match the Zig union ABI size.
                    if (layout.padding != 0) {
                        llvm_fields[llvm_fields_len] = try o.builder.arrayType(layout.padding, .i8);
                        llvm_fields_len += 1;
                    }

                    const ty = try o.builder.opaqueType(try o.builder.string(t.containerTypeName(ip).toSlice(ip)));
                    try o.type_map.put(o.gpa, t.toIntern(), ty);

                    o.builder.namedTypeSetBody(
                        ty,
                        try o.builder.structType(.normal, llvm_fields[0..llvm_fields_len]),
                    );
                    return ty;
                },
                .opaque_type => unreachable, // no runtime bits
                .enum_type => try o.lowerType(t.intTagType(zcu)),
                .func_type => |func_type| try o.lowerFnType(t, func_type),
                .error_set_type, .inferred_error_set_type => try o.errorIntType(),
                // values, not types
                .undef,
                .simple_value,
                .@"extern",
                .func,
                .int,
                .err,
                .error_union,
                .enum_literal,
                .enum_tag,
                .float,
                .ptr,
                .slice,
                .opt,
                .aggregate,
                .un,
                .bitpack,
                // memoization, not types
                .memoized_call,
                => unreachable,
            },
        };
    }

    fn lowerFnType(o: *Object, fn_ty: Type, fn_info: InternPool.Key.FuncType) Allocator.Error!Builder.Type {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const target = zcu.getTarget();

        assert(fn_ty.fnHasRuntimeBits(zcu));

        const ret_ty = try lowerFnRetTy(o, fn_info);

        var llvm_params: std.ArrayList(Builder.Type) = .empty;
        defer llvm_params.deinit(o.gpa);

        if (firstParamSRet(fn_info, zcu, target)) {
            try llvm_params.append(o.gpa, .ptr);
        }

        if (fn_info.cc == .auto and zcu.comp.config.any_error_tracing) {
            // First parameter is a pointer to `std.builtin.StackTrace`.
            const llvm_ptr_ty = try o.builder.ptrType(toLlvmAddressSpace(.generic, target));
            try llvm_params.append(o.gpa, llvm_ptr_ty);
        }

        var it = iterateParamTypes(o, fn_info);
        while (try it.next()) |lowering| switch (lowering) {
            .no_bits => continue,
            .byval => {
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                try llvm_params.append(o.gpa, try o.lowerType(param_ty));
            },
            .byref, .byref_mut => {
                try llvm_params.append(o.gpa, .ptr);
            },
            .abi_sized_int => {
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                try llvm_params.append(o.gpa, try o.builder.intType(
                    @intCast(param_ty.abiSize(zcu) * 8),
                ));
            },
            .slice => {
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                try llvm_params.appendSlice(o.gpa, &.{
                    try o.builder.ptrType(toLlvmAddressSpace(param_ty.ptrAddressSpace(zcu), target)),
                    try o.lowerType(.usize),
                });
            },
            .multiple_llvm_types => {
                try llvm_params.appendSlice(o.gpa, it.types_buffer[0..it.types_len]);
            },
            .float_array => |count| {
                const param_ty = Type.fromInterned(fn_info.param_types.get(ip)[it.zig_index - 1]);
                const float_ty = try o.lowerType(aarch64_c_abi.getFloatArrayType(param_ty, zcu).?);
                try llvm_params.append(o.gpa, try o.builder.arrayType(count, float_ty));
            },
            .i32_array, .i64_array => |arr_len| {
                try llvm_params.append(o.gpa, try o.builder.arrayType(arr_len, switch (lowering) {
                    .i32_array => .i32,
                    .i64_array => .i64,
                    else => unreachable,
                }));
            },
        };

        return o.builder.fnType(
            ret_ty,
            llvm_params.items,
            if (fn_info.is_var_args) .vararg else .normal,
        );
    }

    pub fn lowerValue(o: *Object, arg_val: InternPool.Index) Allocator.Error!Builder.Constant {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const target = zcu.getTarget();

        const val: Value = .fromInterned(arg_val);
        const val_key = ip.indexToKey(val.toIntern());

        const ty: Type = .fromInterned(val_key.typeOf());
        ty.assertHasLayout(zcu);
        assert(ty.hasRuntimeBits(zcu));

        return switch (val_key) {
            .int_type,
            .ptr_type,
            .array_type,
            .vector_type,
            .opt_type,
            .anyframe_type,
            .error_union_type,
            .simple_type,
            .struct_type,
            .tuple_type,
            .union_type,
            .opaque_type,
            .enum_type,
            .func_type,
            .error_set_type,
            .inferred_error_set_type,
            => unreachable, // types, not values

            .undef => return o.builder.undefConst(try o.lowerType(ty)),
            .simple_value => |simple_value| switch (simple_value) {
                .void => unreachable, // non-runtime value
                .null => unreachable, // non-runtime value
                .@"unreachable" => unreachable, // non-runtime value

                .false => .false,
                .true => .true,
            },
            .enum_literal => unreachable, // non-runtime value
            .@"extern" => unreachable, // non-runtime value
            .func => unreachable, // non-runtime value
            .int => {
                var bigint_space: Value.BigIntSpace = undefined;
                const bigint = val.toBigInt(&bigint_space, zcu);
                const llvm_int_ty = try o.builder.intType(ty.intInfo(zcu).bits);
                return o.builder.bigIntConst(llvm_int_ty, bigint);
            },
            .err => |err| {
                const int = zcu.intern_pool.getErrorValueIfExists(err.name).?;
                return o.builder.intConst(try o.errorIntType(), int);
            },
            .error_union => |error_union| {
                const llvm_error_ty = try o.errorIntType();
                const llvm_error_value = switch (error_union.val) {
                    .err_name => |name| try o.builder.intConst(
                        llvm_error_ty,
                        zcu.intern_pool.getErrorValueIfExists(name).?,
                    ),
                    .payload => try o.builder.intConst(llvm_error_ty, 0),
                };

                const payload_type = ty.errorUnionPayload(zcu);
                if (!payload_type.hasRuntimeBits(zcu)) {
                    // We use the error type directly as the type.
                    return llvm_error_value;
                }

                const payload_align = payload_type.abiAlignment(zcu);
                const error_align = Type.errorAbiAlignment(zcu);
                const llvm_payload_value = switch (error_union.val) {
                    .err_name => try o.builder.undefConst(try o.lowerType(payload_type)),
                    .payload => |payload| try o.lowerValue(payload),
                };

                var fields: [3]Builder.Type = undefined;
                var vals: [3]Builder.Constant = undefined;
                if (error_align.compare(.gt, payload_align)) {
                    vals[0] = llvm_error_value;
                    vals[1] = llvm_payload_value;
                } else {
                    vals[0] = llvm_payload_value;
                    vals[1] = llvm_error_value;
                }
                fields[0] = vals[0].typeOf(&o.builder);
                fields[1] = vals[1].typeOf(&o.builder);

                const llvm_ty = try o.lowerType(ty);
                const llvm_ty_fields = llvm_ty.structFields(&o.builder);
                if (llvm_ty_fields.len > 2) {
                    assert(llvm_ty_fields.len == 3);
                    fields[2] = llvm_ty_fields[2];
                    vals[2] = try o.builder.undefConst(fields[2]);
                }
                return o.builder.structConst(try o.builder.structType(
                    llvm_ty.structKind(&o.builder),
                    fields[0..llvm_ty_fields.len],
                ), vals[0..llvm_ty_fields.len]);
            },
            .enum_tag => |enum_tag| o.lowerValue(enum_tag.int),
            .float => switch (ty.floatBits(target)) {
                16 => if (backendSupportsF16(target))
                    try o.builder.halfConst(val.toFloat(f16, zcu))
                else
                    try o.builder.intConst(.i16, @as(i16, @bitCast(val.toFloat(f16, zcu)))),
                32 => try o.builder.floatConst(val.toFloat(f32, zcu)),
                64 => try o.builder.doubleConst(val.toFloat(f64, zcu)),
                80 => if (backendSupportsF80(target))
                    try o.builder.x86_fp80Const(val.toFloat(f80, zcu))
                else
                    try o.builder.intConst(.i80, @as(i80, @bitCast(val.toFloat(f80, zcu)))),
                128 => try o.builder.fp128Const(val.toFloat(f128, zcu)),
                else => unreachable,
            },
            .ptr => try o.lowerPtr(arg_val, 0),
            .slice => |slice| return o.builder.structConst(try o.lowerType(ty), &.{
                try o.lowerValue(slice.ptr),
                try o.lowerValue(slice.len),
            }),
            .opt => |opt| {
                comptime assert(optional_layout_version == 3);
                const payload_ty = ty.optionalChild(zcu);

                const non_null_bit = try o.builder.intConst(.i8, @intFromBool(opt.val != .none));
                if (!payload_ty.hasRuntimeBits(zcu)) {
                    return non_null_bit;
                }
                const llvm_ty = try o.lowerType(ty);
                if (ty.optionalReprIsPayload(zcu)) return switch (opt.val) {
                    .none => switch (llvm_ty.tag(&o.builder)) {
                        .integer => try o.builder.intConst(llvm_ty, 0),
                        .pointer => try o.builder.nullConst(llvm_ty),
                        .structure => try o.builder.zeroInitConst(llvm_ty),
                        else => unreachable,
                    },
                    else => |payload| try o.lowerValue(payload),
                };
                assert(payload_ty.zigTypeTag(zcu) != .@"fn");

                var fields: [3]Builder.Type = undefined;
                var vals: [3]Builder.Constant = undefined;
                vals[0] = switch (opt.val) {
                    .none => try o.builder.undefConst(try o.lowerType(payload_ty)),
                    else => |payload| try o.lowerValue(payload),
                };
                vals[1] = non_null_bit;
                fields[0] = vals[0].typeOf(&o.builder);
                fields[1] = vals[1].typeOf(&o.builder);

                const llvm_ty_fields = llvm_ty.structFields(&o.builder);
                if (llvm_ty_fields.len > 2) {
                    assert(llvm_ty_fields.len == 3);
                    fields[2] = llvm_ty_fields[2];
                    vals[2] = try o.builder.undefConst(fields[2]);
                }
                return o.builder.structConst(try o.builder.structType(
                    llvm_ty.structKind(&o.builder),
                    fields[0..llvm_ty_fields.len],
                ), vals[0..llvm_ty_fields.len]);
            },
            .bitpack => |bitpack| return o.lowerValue(bitpack.backing_int_val),
            .aggregate => |aggregate| switch (ip.indexToKey(ty.toIntern())) {
                .array_type => |array_type| switch (aggregate.storage) {
                    .bytes => |bytes| try o.builder.stringConst(try o.builder.string(
                        bytes.toSlice(array_type.lenIncludingSentinel(), ip),
                    )),
                    .elems => |elems| {
                        const array_ty = try o.lowerType(ty);
                        const elem_ty = array_ty.childType(&o.builder);
                        assert(elems.len == array_ty.aggregateLen(&o.builder));

                        const ExpectedContents = extern struct {
                            vals: [Builder.expected_fields_len]Builder.Constant,
                            fields: [Builder.expected_fields_len]Builder.Type,
                        };
                        var stack align(@max(
                            @alignOf(std.heap.StackFallbackAllocator(0)),
                            @alignOf(ExpectedContents),
                        )) = std.heap.stackFallback(@sizeOf(ExpectedContents), o.gpa);
                        const allocator = stack.get();
                        const vals = try allocator.alloc(Builder.Constant, elems.len);
                        defer allocator.free(vals);
                        const fields = try allocator.alloc(Builder.Type, elems.len);
                        defer allocator.free(fields);

                        var need_unnamed = false;
                        for (vals, fields, elems) |*result_val, *result_field, elem| {
                            result_val.* = try o.lowerValue(elem);
                            result_field.* = result_val.typeOf(&o.builder);
                            if (result_field.* != elem_ty) need_unnamed = true;
                        }
                        return if (need_unnamed) try o.builder.structConst(
                            try o.builder.structType(.normal, fields),
                            vals,
                        ) else try o.builder.arrayConst(array_ty, vals);
                    },
                    .repeated_elem => |elem| {
                        const len: usize = @intCast(array_type.len);
                        const len_including_sentinel: usize = @intCast(array_type.lenIncludingSentinel());
                        const array_ty = try o.lowerType(ty);
                        const elem_ty = array_ty.childType(&o.builder);

                        const ExpectedContents = extern struct {
                            vals: [Builder.expected_fields_len]Builder.Constant,
                            fields: [Builder.expected_fields_len]Builder.Type,
                        };
                        var stack align(@max(
                            @alignOf(std.heap.StackFallbackAllocator(0)),
                            @alignOf(ExpectedContents),
                        )) = std.heap.stackFallback(@sizeOf(ExpectedContents), o.gpa);
                        const allocator = stack.get();
                        const vals = try allocator.alloc(Builder.Constant, len_including_sentinel);
                        defer allocator.free(vals);
                        const fields = try allocator.alloc(Builder.Type, len_including_sentinel);
                        defer allocator.free(fields);

                        var need_unnamed = false;
                        @memset(vals[0..len], try o.lowerValue(elem));
                        @memset(fields[0..len], vals[0].typeOf(&o.builder));
                        if (fields[0] != elem_ty) need_unnamed = true;

                        if (array_type.sentinel != .none) {
                            vals[len] = try o.lowerValue(array_type.sentinel);
                            fields[len] = vals[len].typeOf(&o.builder);
                            if (fields[len] != elem_ty) need_unnamed = true;
                        }

                        return if (need_unnamed) try o.builder.structConst(
                            try o.builder.structType(.@"packed", fields),
                            vals,
                        ) else try o.builder.arrayConst(array_ty, vals);
                    },
                },
                .vector_type => |vector_type| {
                    const vector_ty = try o.lowerType(ty);
                    switch (aggregate.storage) {
                        .bytes, .elems => {
                            const ExpectedContents = [Builder.expected_fields_len]Builder.Constant;
                            var stack align(@max(
                                @alignOf(std.heap.StackFallbackAllocator(0)),
                                @alignOf(ExpectedContents),
                            )) = std.heap.stackFallback(@sizeOf(ExpectedContents), o.gpa);
                            const allocator = stack.get();
                            const vals = try allocator.alloc(Builder.Constant, vector_type.len);
                            defer allocator.free(vals);

                            switch (aggregate.storage) {
                                .bytes => |bytes| for (vals, bytes.toSlice(vector_type.len, ip)) |*result_val, byte| {
                                    result_val.* = try o.builder.intConst(.i8, byte);
                                },
                                .elems => |elems| for (vals, elems) |*result_val, elem| {
                                    result_val.* = try o.lowerValue(elem);
                                },
                                .repeated_elem => unreachable,
                            }
                            return o.builder.vectorConst(vector_ty, vals);
                        },
                        .repeated_elem => |elem| return o.builder.splatConst(
                            vector_ty,
                            try o.lowerValue(elem),
                        ),
                    }
                },
                .tuple_type => |tuple| {
                    const struct_ty = try o.lowerType(ty);
                    const llvm_len = struct_ty.aggregateLen(&o.builder);

                    const ExpectedContents = extern struct {
                        vals: [Builder.expected_fields_len]Builder.Constant,
                        fields: [Builder.expected_fields_len]Builder.Type,
                    };
                    var stack align(@max(
                        @alignOf(std.heap.StackFallbackAllocator(0)),
                        @alignOf(ExpectedContents),
                    )) = std.heap.stackFallback(@sizeOf(ExpectedContents), o.gpa);
                    const allocator = stack.get();
                    const vals = try allocator.alloc(Builder.Constant, llvm_len);
                    defer allocator.free(vals);
                    const fields = try allocator.alloc(Builder.Type, llvm_len);
                    defer allocator.free(fields);

                    comptime assert(struct_layout_version == 2);
                    var llvm_index: usize = 0;
                    var offset: u64 = 0;
                    var big_align: InternPool.Alignment = .@"1";
                    var need_unnamed = false;
                    for (
                        tuple.types.get(ip),
                        tuple.values.get(ip),
                        0..,
                    ) |field_ty, field_comptime_val, field_index| {
                        if (field_comptime_val != .none) continue;
                        if (!Type.fromInterned(field_ty).hasRuntimeBits(zcu)) continue;

                        const field_align = Type.fromInterned(field_ty).abiAlignment(zcu);
                        big_align = big_align.max(field_align);
                        const prev_offset = offset;
                        offset = field_align.forward(offset);

                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) {
                            // TODO make this and all other padding elsewhere in debug
                            // builds be 0xaa not undef.
                            fields[llvm_index] = try o.builder.arrayType(padding_len, .i8);
                            vals[llvm_index] = try o.builder.undefConst(fields[llvm_index]);
                            assert(fields[llvm_index] == struct_ty.structFields(&o.builder)[llvm_index]);
                            llvm_index += 1;
                        }

                        vals[llvm_index] = switch (aggregate.storage) {
                            .bytes => |bytes| try o.builder.intConst(.i8, bytes.at(field_index, ip)),
                            .elems => |elems| try o.lowerValue(elems[field_index]),
                            .repeated_elem => |elem| try o.lowerValue(elem),
                        };
                        fields[llvm_index] = vals[llvm_index].typeOf(&o.builder);
                        if (fields[llvm_index] != struct_ty.structFields(&o.builder)[llvm_index])
                            need_unnamed = true;
                        llvm_index += 1;

                        offset += Type.fromInterned(field_ty).abiSize(zcu);
                    }
                    {
                        const prev_offset = offset;
                        offset = big_align.forward(offset);
                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) {
                            fields[llvm_index] = try o.builder.arrayType(padding_len, .i8);
                            vals[llvm_index] = try o.builder.undefConst(fields[llvm_index]);
                            assert(fields[llvm_index] == struct_ty.structFields(&o.builder)[llvm_index]);
                            llvm_index += 1;
                        }
                    }
                    assert(llvm_index == llvm_len);

                    return o.builder.structConst(if (need_unnamed)
                        try o.builder.structType(struct_ty.structKind(&o.builder), fields)
                    else
                        struct_ty, vals);
                },
                .struct_type => {
                    const struct_type = ip.loadStructType(ty.toIntern());
                    const struct_ty = try o.lowerType(ty);
                    assert(struct_type.layout != .@"packed");
                    const llvm_len = struct_ty.aggregateLen(&o.builder);

                    const ExpectedContents = extern struct {
                        vals: [Builder.expected_fields_len]Builder.Constant,
                        fields: [Builder.expected_fields_len]Builder.Type,
                    };
                    var stack align(@max(
                        @alignOf(std.heap.StackFallbackAllocator(0)),
                        @alignOf(ExpectedContents),
                    )) = std.heap.stackFallback(@sizeOf(ExpectedContents), o.gpa);
                    const allocator = stack.get();
                    const vals = try allocator.alloc(Builder.Constant, llvm_len);
                    defer allocator.free(vals);
                    const fields = try allocator.alloc(Builder.Type, llvm_len);
                    defer allocator.free(fields);

                    comptime assert(struct_layout_version == 2);
                    var llvm_index: usize = 0;
                    var offset: u64 = 0;
                    var need_unnamed = false;
                    var field_it = struct_type.iterateRuntimeOrder(ip);
                    while (field_it.next()) |field_index| {
                        const field_ty = Type.fromInterned(struct_type.field_types.get(ip)[field_index]);
                        const prev_offset = offset;
                        offset = struct_type.field_offsets.get(ip)[field_index];

                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) {
                            // TODO make this and all other padding elsewhere in debug
                            // builds be 0xaa not undef.
                            fields[llvm_index] = try o.builder.arrayType(padding_len, .i8);
                            vals[llvm_index] = try o.builder.undefConst(fields[llvm_index]);
                            assert(fields[llvm_index] ==
                                struct_ty.structFields(&o.builder)[llvm_index]);
                            llvm_index += 1;
                        }

                        if (!field_ty.hasRuntimeBits(zcu)) {
                            // This is a zero-bit field - we only needed it for the alignment.
                            continue;
                        }

                        vals[llvm_index] = switch (aggregate.storage) {
                            .bytes => |bytes| try o.builder.intConst(.i8, bytes.at(field_index, ip)),
                            .elems => |elems| try o.lowerValue(elems[field_index]),
                            .repeated_elem => |elem| try o.lowerValue(elem),
                        };
                        fields[llvm_index] = vals[llvm_index].typeOf(&o.builder);
                        if (fields[llvm_index] != struct_ty.structFields(&o.builder)[llvm_index])
                            need_unnamed = true;
                        llvm_index += 1;

                        offset += field_ty.abiSize(zcu);
                    }
                    {
                        const prev_offset = offset;
                        offset = struct_type.alignment.forward(offset);
                        const padding_len = offset - prev_offset;
                        if (padding_len > 0) {
                            fields[llvm_index] = try o.builder.arrayType(padding_len, .i8);
                            vals[llvm_index] = try o.builder.undefConst(fields[llvm_index]);
                            assert(fields[llvm_index] == struct_ty.structFields(&o.builder)[llvm_index]);
                            llvm_index += 1;
                        }
                    }
                    assert(llvm_index == llvm_len);

                    return o.builder.structConst(if (need_unnamed)
                        try o.builder.structType(struct_ty.structKind(&o.builder), fields)
                    else
                        struct_ty, vals);
                },
                else => unreachable,
            },
            .un => |un| {
                const union_ty = try o.lowerType(ty);
                const layout = ty.unionGetLayout(zcu);
                if (layout.payload_size == 0) return o.lowerValue(un.tag);

                const union_obj = zcu.typeToUnion(ty).?;
                const container_layout = union_obj.layout;
                assert(container_layout != .@"packed");

                var need_unnamed = false;
                const payload = if (un.tag != .none) p: {
                    const field_index = zcu.unionTagFieldIndex(union_obj, Value.fromInterned(un.tag)).?;
                    const field_ty = Type.fromInterned(union_obj.field_types.get(ip)[field_index]);

                    // Sometimes we must make an unnamed struct because LLVM does
                    // not support bitcasting our payload struct to the true union payload type.
                    // Instead we use an unnamed struct and every reference to the global
                    // must pointer cast to the expected type before accessing the union.
                    need_unnamed = layout.most_aligned_field != field_index;

                    if (!field_ty.hasRuntimeBits(zcu)) {
                        const padding_len = layout.payload_size;
                        break :p try o.builder.undefConst(try o.builder.arrayType(padding_len, .i8));
                    }
                    const payload = try o.lowerValue(un.val);
                    const payload_ty = payload.typeOf(&o.builder);
                    if (payload_ty != union_ty.structFields(&o.builder)[
                        @intFromBool(layout.tag_size > 0 and layout.tag_align.compare(.gte, layout.payload_align))
                    ]) need_unnamed = true;
                    const field_size = field_ty.abiSize(zcu);
                    if (field_size == layout.payload_size) break :p payload;
                    const padding_len = layout.payload_size - field_size;
                    const padding_ty = try o.builder.arrayType(padding_len, .i8);
                    break :p try o.builder.structConst(
                        try o.builder.structType(.@"packed", &.{ payload_ty, padding_ty }),
                        &.{ payload, try o.builder.undefConst(padding_ty) },
                    );
                } else p: {
                    assert(layout.tag_size == 0);
                    const union_val = try o.lowerValue(un.val);
                    need_unnamed = true;
                    break :p union_val;
                };

                const payload_ty = payload.typeOf(&o.builder);
                if (layout.tag_size == 0) return o.builder.structConst(if (need_unnamed)
                    try o.builder.structType(union_ty.structKind(&o.builder), &.{payload_ty})
                else
                    union_ty, &.{payload});
                const tag = try o.lowerValue(un.tag);
                const tag_ty = tag.typeOf(&o.builder);
                var fields: [3]Builder.Type = undefined;
                var vals: [3]Builder.Constant = undefined;
                var len: usize = 2;
                if (layout.tag_align.compare(.gte, layout.payload_align)) {
                    fields = .{ tag_ty, payload_ty, undefined };
                    vals = .{ tag, payload, undefined };
                } else {
                    fields = .{ payload_ty, tag_ty, undefined };
                    vals = .{ payload, tag, undefined };
                }
                if (layout.padding != 0) {
                    fields[2] = try o.builder.arrayType(layout.padding, .i8);
                    vals[2] = try o.builder.undefConst(fields[2]);
                    len = 3;
                }
                return o.builder.structConst(if (need_unnamed)
                    try o.builder.structType(union_ty.structKind(&o.builder), fields[0..len])
                else
                    union_ty, vals[0..len]);
            },
            .memoized_call => unreachable,
        };
    }

    fn lowerPtr(
        o: *Object,
        ptr_val: InternPool.Index,
        prev_offset: u64,
    ) Allocator.Error!Builder.Constant {
        const zcu = o.zcu;
        const ptr = zcu.intern_pool.indexToKey(ptr_val).ptr;
        const offset: u64 = prev_offset + ptr.byte_offset;
        return switch (ptr.base_addr) {
            .nav => |nav| {
                const base_ptr = try o.lowerNavRef(nav);
                return o.builder.gepConst(.inbounds, .i8, base_ptr, null, &.{
                    try o.builder.intConst(.i64, offset),
                });
            },
            .uav => |uav| {
                const orig_ptr_ty: Type = .fromInterned(uav.orig_ty);
                const base_ptr = try o.lowerUavRef(
                    uav.val,
                    orig_ptr_ty.ptrAlignment(zcu),
                    orig_ptr_ty.ptrAddressSpace(zcu),
                );
                return o.builder.gepConst(.inbounds, .i8, base_ptr, null, &.{
                    try o.builder.intConst(.i64, offset),
                });
            },
            .int => try o.builder.castConst(
                .inttoptr,
                try o.builder.intConst(try o.lowerType(.usize), offset),
                try o.lowerType(.fromInterned(ptr.ty)),
            ),
            .eu_payload => |eu_ptr| try o.lowerPtr(
                eu_ptr,
                offset + codegen.errUnionPayloadOffset(
                    Value.fromInterned(eu_ptr).typeOf(zcu).childType(zcu),
                    zcu,
                ),
            ),
            .opt_payload => |opt_ptr| try o.lowerPtr(opt_ptr, offset),
            .field => |field| {
                const agg_ty = Value.fromInterned(field.base).typeOf(zcu).childType(zcu);
                const field_off: u64 = switch (agg_ty.zigTypeTag(zcu)) {
                    .pointer => off: {
                        assert(agg_ty.isSlice(zcu));
                        break :off switch (field.index) {
                            Value.slice_ptr_index => 0,
                            Value.slice_len_index => @divExact(zcu.getTarget().ptrBitWidth(), 8),
                            else => unreachable,
                        };
                    },
                    .@"struct", .@"union" => switch (agg_ty.containerLayout(zcu)) {
                        .auto => agg_ty.structFieldOffset(@intCast(field.index), zcu),
                        .@"extern", .@"packed" => unreachable,
                    },
                    else => unreachable,
                };
                return o.lowerPtr(field.base, offset + field_off);
            },
            .arr_elem => |arr_elem| {
                const base_ptr_ty = Value.fromInterned(arr_elem.base).typeOf(zcu);
                assert(base_ptr_ty.ptrSize(zcu) == .many);
                const elem_size = base_ptr_ty.childType(zcu).abiSize(zcu);
                return o.lowerPtr(arr_elem.base, offset + elem_size * arr_elem.index);
            },
            .comptime_field => unreachable,
            .comptime_alloc => unreachable,
        };
    }

    pub fn lowerPtrToVoid(
        o: *Object,
        /// Must not be `.none`.
        @"align": InternPool.Alignment,
        @"addrspace": std.builtin.AddressSpace,
    ) Allocator.Error!Builder.Constant {
        const addr: u64 = @"align".toByteUnits().?;
        const llvm_usize = try o.lowerType(.usize);
        const llvm_addr = try o.builder.intConst(llvm_usize, addr);
        const llvm_ptr_ty = try o.builder.ptrType(toLlvmAddressSpace(@"addrspace", o.zcu.getTarget()));
        return o.builder.castConst(.inttoptr, llvm_addr, llvm_ptr_ty);
    }

    pub fn lowerUavRef(
        o: *Object,
        uav_val: InternPool.Index,
        /// Must not be `.none`.
        @"align": InternPool.Alignment,
        @"addrspace": std.builtin.AddressSpace,
    ) Allocator.Error!Builder.Constant {
        assert(@"align" != .none);

        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const gpa = zcu.comp.gpa;

        const uav_ty: Type = .fromInterned(ip.typeOf(uav_val));

        switch (ip.indexToKey(uav_val)) {
            .func => unreachable, // should be using a Nav ref
            .@"extern" => unreachable, // should be using a Nav ref
            else => {},
        }

        if (!uav_ty.hasRuntimeBits(zcu)) {
            return o.lowerPtrToVoid(@"align", @"addrspace");
        }

        const llvm_addrspace = toLlvmAddressSpace(@"addrspace", zcu.getTarget());

        const gop = try o.uav_map.getOrPut(gpa, .{ .val = uav_val, .@"addrspace" = @"addrspace" });
        if (gop.found_existing) {
            // Keep the greater of the two alignments.
            const llvm_variable = gop.value_ptr.*;
            const old_align: InternPool.Alignment = .fromLlvm(llvm_variable.getAlignment(&o.builder));
            llvm_variable.setAlignment(old_align.maxStrict(@"align").toLlvm(), &o.builder);
            return llvm_variable.ptrConst(&o.builder).global.toConst();
        }
        errdefer assert(o.uav_map.remove(.{ .val = uav_val, .@"addrspace" = @"addrspace" }));

        const llvm_ty = try o.lowerType(uav_ty);
        const llvm_name = try o.builder.strtabStringFmt("__anon_{d}", .{@intFromEnum(uav_val)});
        const llvm_variable = try o.builder.addVariable(llvm_name, llvm_ty, llvm_addrspace);
        gop.value_ptr.* = llvm_variable;
        try llvm_variable.setInitializer(try o.lowerValue(uav_val), &o.builder);
        llvm_variable.setMutability(.constant, &o.builder);
        llvm_variable.setAlignment(@"align".toLlvm(), &o.builder);
        const llvm_global = llvm_variable.ptrConst(&o.builder).global;
        llvm_global.setLinkage(if (o.builder.strip) .private else .internal, &o.builder);
        llvm_global.setUnnamedAddr(.unnamed_addr, &o.builder);
        return llvm_global.toConst();
    }

    pub fn lowerNavRef(o: *Object, nav_id: InternPool.Nav.Index) Allocator.Error!Builder.Constant {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const gpa = zcu.comp.gpa;

        const nav = ip.getNav(nav_id);
        const nav_ty: Type = .fromInterned(nav.resolved.?.type);
        if (!nav_ty.isRuntimeFnOrHasRuntimeBits(zcu) and nav.getExtern(ip) == null) {
            const nav_align = switch (nav.resolved.?.@"align") {
                .none => nav_ty.abiAlignment(zcu),
                else => |a| a,
            };
            return o.lowerPtrToVoid(nav_align, nav.resolved.?.@"addrspace");
        }

        const gop = try o.nav_map.getOrPut(gpa, nav_id);
        if (!gop.found_existing) {
            errdefer assert(o.nav_map.remove(nav_id));
            // The NAV hasn't been lowered yet, so generate a placeholder global whose details will
            // be filled in later.
            const llvm_name = try o.builder.strtabString(nav.fqn.toSlice(ip));
            gop.value_ptr.* = try o.builder.addGlobal(llvm_name, .{
                .type = .void, // placeholder; populated by `updateNav`/`updateFunc`
                .kind = .{ .alias = .none }, // placeholder; populated by `updateNav`/`updateFunc`
            });
        }
        const llvm_global = gop.value_ptr.*;

        // We need to make sure the global's address space is up to date, because that affects the
        // type of a pointer to this global. But everything else about the global will be populated
        // by `updateNav` or `updateFunc`.
        llvm_global.ptr(&o.builder).addr_space = toLlvmAddressSpace(nav.resolved.?.@"addrspace", zcu.getTarget());
        return llvm_global.toConst();
    }

    pub fn addByValParamAttrs(
        o: *Object,
        pt: Zcu.PerThread,
        attributes: *Builder.FunctionAttributes.Wip,
        param_ty: Type,
        param_index: u32,
        fn_info: InternPool.Key.FuncType,
        llvm_arg_i: u32,
    ) Allocator.Error!void {
        const zcu = o.zcu;
        if (param_ty.isPtrAtRuntime(zcu)) {
            const ptr_info = param_ty.ptrInfo(zcu);
            if (std.math.cast(u5, param_index)) |i| {
                if (@as(u1, @truncate(fn_info.noalias_bits >> i)) != 0) {
                    try attributes.addParamAttr(llvm_arg_i, .@"noalias", &o.builder);
                }
            }
            if (!param_ty.isPtrLikeOptional(zcu) and
                !ptr_info.flags.is_allowzero and
                ptr_info.flags.address_space == .generic)
            {
                try attributes.addParamAttr(llvm_arg_i, .nonnull, &o.builder);
            }
            switch (fn_info.cc) {
                else => {},
                .x86_64_interrupt,
                .x86_interrupt,
                => {
                    const child_type = try lowerType(o, Type.fromInterned(ptr_info.child));
                    try attributes.addParamAttr(llvm_arg_i, .{ .byval = child_type }, &o.builder);
                },
            }
            if (ptr_info.flags.is_const) {
                try attributes.addParamAttr(llvm_arg_i, .readonly, &o.builder);
            }
            const elem_align: Builder.Alignment.Lazy = switch (ptr_info.flags.alignment) {
                else => |a| .wrap(a.toLlvm()),
                .none => try o.lazyAbiAlignment(pt, .fromInterned(ptr_info.child)),
            };
            try attributes.addParamAttr(llvm_arg_i, .{ .@"align" = elem_align }, &o.builder);
        } else if (ccAbiPromoteInt(fn_info.cc, zcu, param_ty)) |s| switch (s) {
            .signed => try attributes.addParamAttr(llvm_arg_i, .signext, &o.builder),
            .unsigned => try attributes.addParamAttr(llvm_arg_i, .zeroext, &o.builder),
        };
    }

    pub fn addByRefParamAttrs(
        o: *Object,
        attributes: *Builder.FunctionAttributes.Wip,
        llvm_arg_i: u32,
        alignment: Builder.Alignment,
        byval: bool,
        param_llvm_ty: Builder.Type,
    ) Allocator.Error!void {
        try attributes.addParamAttr(llvm_arg_i, .nonnull, &o.builder);
        try attributes.addParamAttr(llvm_arg_i, .readonly, &o.builder);
        try attributes.addParamAttr(llvm_arg_i, .{ .@"align" = .wrap(alignment) }, &o.builder);
        if (byval) try attributes.addParamAttr(llvm_arg_i, .{ .byval = param_llvm_ty }, &o.builder);
    }

    pub fn getErrorNameTable(o: *Object) Allocator.Error!Builder.Variable.Index {
        if (o.error_name_table != .none) return o.error_name_table;

        const name = try o.builder.strtabString("__zig_error_name_table");
        // TODO: Address space
        const variable_index = try o.builder.addVariable(name, .ptr, .default);
        variable_index.setMutability(.constant, &o.builder);
        variable_index.setAlignment(
            Type.slice_const_u8_sentinel_0.abiAlignment(o.zcu).toLlvm(),
            &o.builder,
        );
        const global_index = variable_index.ptrConst(&o.builder).global;
        global_index.setLinkage(.private, &o.builder);
        global_index.setUnnamedAddr(.unnamed_addr, &o.builder);

        o.error_name_table = variable_index;
        return variable_index;
    }

    pub fn getErrorsLen(o: *Object) Allocator.Error!Builder.Variable.Index {
        const builder = &o.builder;
        if (o.errors_len_variable == .none) {
            const llvm_err_int_ty = try o.errorIntType();
            const name = try builder.strtabString("__zig_errors_len");
            const variable_index = try builder.addVariable(name, llvm_err_int_ty, .default);
            variable_index.setMutability(.constant, builder);
            variable_index.setAlignment(Type.errorAbiAlignment(o.zcu).toLlvm(), builder);
            const global_index = variable_index.ptrConst(&o.builder).global;
            global_index.setLinkage(.private, builder);
            global_index.setUnnamedAddr(.unnamed_addr, builder);
            o.errors_len_variable = variable_index;
        }
        return o.errors_len_variable;
    }

    pub fn getEnumTagNameFunction(o: *Object, enum_ty: Type) Allocator.Error!Builder.Function.Index {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;

        const gop = try o.enum_tag_name_map.getOrPut(o.gpa, enum_ty.toIntern());
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer assert(o.enum_tag_name_map.remove(enum_ty.toIntern()));
        const function_index = try o.builder.addFunction(
            // Dummy function type; `updateEnumTagNameFunction` will replace it with the correct type.
            // TODO: change the builder API so we don't need to do this.
            try o.builder.fnType(.void, &.{}, .normal),
            try o.builder.strtabStringFmt("__zig_tag_name_{f}", .{enum_ty.containerTypeName(ip).fmt(ip)}),
            toLlvmAddressSpace(.generic, zcu.getTarget()),
        );
        gop.value_ptr.* = function_index;
        try o.updateEnumTagNameFunction(enum_ty, function_index);
        return function_index;
    }
    fn updateEnumTagNameFunction(
        o: *Object,
        enum_ty: Type,
        function_index: Builder.Function.Index,
    ) Allocator.Error!void {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const loaded_enum = ip.loadEnumType(enum_ty.toIntern());

        const llvm_usize_ty = try o.lowerType(.usize);
        const llvm_ret_ty = try o.lowerType(.slice_const_u8_sentinel_0);
        const llvm_int_ty = try o.lowerType(.fromInterned(loaded_enum.int_tag_type));

        function_index.ptrConst(&o.builder).global.ptr(&o.builder).type =
            try o.builder.fnType(llvm_ret_ty, &.{llvm_int_ty}, .normal);

        var attributes: Builder.FunctionAttributes.Wip = .{};
        defer attributes.deinit(&o.builder);
        try o.addCommonFnAttributes(&attributes, zcu.root_mod, zcu.root_mod.omit_frame_pointer);

        function_index.setLinkage(if (o.builder.strip) .private else .internal, &o.builder);
        function_index.setCallConv(.fastcc, &o.builder);
        function_index.setAttributes(try attributes.finish(&o.builder), &o.builder);

        var wip = try Builder.WipFunction.init(&o.builder, .{
            .function = function_index,
            .strip = true,
        });
        defer wip.deinit();
        wip.cursor = .{ .block = try wip.block(0, "Entry") };

        const bad_value_block = try wip.block(1, "BadValue");
        const tag_int_value = wip.arg(0);
        var wip_switch = try wip.@"switch"(
            tag_int_value,
            bad_value_block,
            @intCast(loaded_enum.field_names.len),
            .none,
        );
        defer wip_switch.finish(&wip);

        for (0..loaded_enum.field_names.len) |field_index| {
            const name = try o.builder.stringNull(loaded_enum.field_names.get(ip)[field_index].toSlice(ip));
            const name_init = try o.builder.stringConst(name);
            const name_variable_index = try o.builder.addVariable(.empty, name_init.typeOf(&o.builder), .default);
            try name_variable_index.setInitializer(name_init, &o.builder);
            name_variable_index.setMutability(.constant, &o.builder);
            name_variable_index.setAlignment(comptime Builder.Alignment.fromByteUnits(1), &o.builder);
            const name_global_index = name_variable_index.ptrConst(&o.builder).global;
            name_global_index.setLinkage(.private, &o.builder);
            name_global_index.setUnnamedAddr(.unnamed_addr, &o.builder);

            const name_val = try o.builder.structValue(llvm_ret_ty, &.{
                name_global_index.toConst(),
                try o.builder.intConst(llvm_usize_ty, name.slice(&o.builder).?.len - 1),
            });

            const return_block = try wip.block(1, "Name");
            const llvm_tag_val = switch (loaded_enum.field_values.getOrNone(ip, field_index)) {
                .none => try o.builder.intConst(llvm_int_ty, field_index), // auto-numbered
                else => |tag_val_ip| try o.lowerValue(tag_val_ip),
            };
            try wip_switch.addCase(llvm_tag_val, return_block, &wip);

            wip.cursor = .{ .block = return_block };
            _ = try wip.ret(name_val);
        }

        wip.cursor = .{ .block = bad_value_block };
        _ = try wip.@"unreachable"();

        try wip.finish();
    }

    pub fn lazyAbiAlignment(o: *Object, pt: Zcu.PerThread, ty: Type) Allocator.Error!Builder.Alignment.Lazy {
        const index = try o.type_pool.get(pt, .{ .llvm = o }, ty.toIntern());
        return o.lazy_abi_aligns.items[@intFromEnum(index)];
    }

    pub fn getIsNamedEnumValueFunction(o: *Object, enum_ty: Type) Allocator.Error!Builder.Function.Index {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;

        const gop = try o.named_enum_map.getOrPut(o.gpa, enum_ty.toIntern());
        if (gop.found_existing) return gop.value_ptr.*;
        errdefer assert(o.named_enum_map.remove(enum_ty.toIntern()));
        const function_index = try o.builder.addFunction(
            // Dummy function type; `updateIsNamedEnumValue` will replace it with the correct type.
            // TODO: change the builder API so we don't need to do this.
            try o.builder.fnType(.void, &.{}, .normal),
            try o.builder.strtabStringFmt("__zig_is_named_enum_value_{f}", .{enum_ty.containerTypeName(ip).fmt(ip)}),
            toLlvmAddressSpace(.generic, zcu.getTarget()),
        );
        gop.value_ptr.* = function_index;
        try o.updateIsNamedEnumValueFunction(enum_ty, function_index);
        return function_index;
    }
    fn updateIsNamedEnumValueFunction(
        o: *Object,
        enum_ty: Type,
        function_index: Builder.Function.Index,
    ) Allocator.Error!void {
        const zcu = o.zcu;
        const ip = &zcu.intern_pool;
        const loaded_enum = ip.loadEnumType(enum_ty.toIntern());

        const llvm_int_ty = try o.lowerType(.fromInterned(loaded_enum.int_tag_type));
        function_index.ptrConst(&o.builder).global.ptr(&o.builder).type =
            try o.builder.fnType(.i1, &.{llvm_int_ty}, .normal);

        var attributes: Builder.FunctionAttributes.Wip = .{};
        defer attributes.deinit(&o.builder);
        try o.addCommonFnAttributes(&attributes, zcu.root_mod, zcu.root_mod.omit_frame_pointer);

        function_index.setLinkage(if (o.builder.strip) .private else .internal, &o.builder);
        function_index.setCallConv(.fastcc, &o.builder);
        function_index.setAttributes(try attributes.finish(&o.builder), &o.builder);

        var wip: Builder.WipFunction = try .init(&o.builder, .{
            .function = function_index,
            .strip = true,
        });
        defer wip.deinit();
        wip.cursor = .{ .block = try wip.block(0, "Entry") };

        const named_block = try wip.block(@intCast(loaded_enum.field_names.len), "Named");
        const unnamed_block = try wip.block(1, "Unnamed");
        const tag_int_value = wip.arg(0);
        var wip_switch = try wip.@"switch"(tag_int_value, unnamed_block, @intCast(loaded_enum.field_names.len), .none);
        defer wip_switch.finish(&wip);

        if (loaded_enum.field_values.len > 0) {
            for (loaded_enum.field_values.get(ip)) |tag_val_ip| {
                const llvm_tag_val = try o.lowerValue(tag_val_ip);
                try wip_switch.addCase(llvm_tag_val, named_block, &wip);
            }
        } else {
            // Auto-numbered.
            for (0..loaded_enum.field_names.len) |field_index| {
                const llvm_tag_val = try o.builder.intConst(llvm_int_ty, field_index);
                try wip_switch.addCase(llvm_tag_val, named_block, &wip);
            }
        }

        wip.cursor = .{ .block = named_block };
        _ = try wip.ret(.true);

        wip.cursor = .{ .block = unnamed_block };
        _ = try wip.ret(.false);

        try wip.finish();
    }

    pub fn getLibcFunction(
        o: *Object,
        fn_name: Builder.StrtabString,
        param_types: []const Builder.Type,
        return_type: Builder.Type,
    ) Allocator.Error!Builder.Function.Index {
        if (o.builder.getGlobal(fn_name)) |global| return switch (global.ptrConst(&o.builder).kind) {
            .alias => |alias| alias.getAliasee(&o.builder).ptrConst(&o.builder).kind.function,
            .function => |function| function,
            .variable, .replaced => unreachable,
        };
        return o.builder.addFunction(
            try o.builder.fnType(return_type, param_types, .normal),
            fn_name,
            toLlvmAddressSpace(.generic, o.zcu.getTarget()),
        );
    }
};

const CallingConventionInfo = struct {
    /// The LLVM calling convention to use.
    llvm_cc: Builder.CallConv,
    /// Whether to use an `alignstack` attribute to forcibly re-align the stack pointer in the function's prologue.
    align_stack: bool,
    /// Whether the function needs a `naked` attribute.
    naked: bool,
    /// How many leading parameters to apply the `inreg` attribute to.
    inreg_param_count: u2 = 0,
};

pub fn toLlvmCallConv(cc: std.builtin.CallingConvention, target: *const std.Target) ?CallingConventionInfo {
    const llvm_cc = toLlvmCallConvTag(cc, target) orelse return null;
    const incoming_stack_alignment: ?u64, const register_params: u2 = switch (cc) {
        inline else => |pl| switch (@TypeOf(pl)) {
            void => .{ null, 0 },
            std.builtin.CallingConvention.ArcInterruptOptions,
            std.builtin.CallingConvention.ArmInterruptOptions,
            std.builtin.CallingConvention.RiscvInterruptOptions,
            std.builtin.CallingConvention.ShInterruptOptions,
            std.builtin.CallingConvention.MicroblazeInterruptOptions,
            std.builtin.CallingConvention.MipsInterruptOptions,
            std.builtin.CallingConvention.CommonOptions,
            => .{ pl.incoming_stack_alignment, 0 },
            std.builtin.CallingConvention.X86RegparmOptions => .{ pl.incoming_stack_alignment, pl.register_params },
            else => @compileError("TODO: toLlvmCallConv" ++ @tagName(pl)),
        },
    };
    return .{
        .llvm_cc = llvm_cc,
        .align_stack = if (incoming_stack_alignment) |a| need_align: {
            const normal_stack_align = target.stackAlignment();
            break :need_align a < normal_stack_align;
        } else false,
        .naked = cc == .naked,
        .inreg_param_count = register_params,
    };
}
pub fn toLlvmCallConvTag(cc_tag: std.builtin.CallingConvention.Tag, target: *const std.Target) ?Builder.CallConv {
    if (target.cCallingConvention()) |default_c| {
        if (cc_tag == default_c) {
            return .ccc;
        }
    }
    return switch (cc_tag) {
        .@"inline" => unreachable,
        .auto, .async => .fastcc,
        .naked => .ccc,
        .x86_64_sysv => .x86_64_sysvcc,
        .x86_64_win => .win64cc,
        .x86_64_regcall_v3_sysv => if (target.cpu.arch == .x86_64 and target.os.tag != .windows)
            .x86_regcallcc
        else
            null,
        .x86_64_regcall_v4_win => if (target.cpu.arch == .x86_64 and target.os.tag == .windows)
            .x86_regcallcc // we use the "RegCallv4" module flag to make this correct
        else
            null,
        .x86_64_vectorcall => .x86_vectorcallcc,
        .x86_64_interrupt => .x86_intrcc,
        .x86_stdcall => .x86_stdcallcc,
        .x86_fastcall => .x86_fastcallcc,
        .x86_thiscall => .x86_thiscallcc,
        .x86_regcall_v3 => if (target.cpu.arch == .x86 and target.os.tag != .windows)
            .x86_regcallcc
        else
            null,
        .x86_regcall_v4_win => if (target.cpu.arch == .x86 and target.os.tag == .windows)
            .x86_regcallcc // we use the "RegCallv4" module flag to make this correct
        else
            null,
        .x86_vectorcall => .x86_vectorcallcc,
        .x86_interrupt => .x86_intrcc,
        .aarch64_vfabi => .aarch64_vector_pcs,
        .aarch64_vfabi_sve => .aarch64_sve_vector_pcs,
        .arm_aapcs => .arm_aapcscc,
        .arm_aapcs_vfp => .arm_aapcs_vfpcc,
        .riscv64_lp64_v => .riscv_vectorcallcc,
        .riscv32_ilp32_v => .riscv_vectorcallcc,
        .avr_builtin => .avr_builtincc,
        .avr_signal => .avr_signalcc,
        .avr_interrupt => .avr_intrcc,
        .m68k_rtd => .m68k_rtdcc,
        .m68k_interrupt => .m68k_intrcc,
        .msp430_interrupt => .msp430_intrcc,
        .amdgcn_kernel => .amdgpu_kernel,
        .amdgcn_cs => .amdgpu_cs,
        .nvptx_device => .ptx_device,
        .nvptx_kernel => .ptx_kernel,

        // Calling conventions which LLVM uses function attributes for.
        .riscv64_interrupt,
        .riscv32_interrupt,
        .arm_interrupt,
        .mips64_interrupt,
        .mips_interrupt,
        .csky_interrupt,
        => .ccc,

        // All the calling conventions which LLVM does not have a general representation for.
        // Note that these are often still supported through the `cCallingConvention` path above via `ccc`.
        .x86_16_cdecl,
        .x86_16_stdcall,
        .x86_16_regparmcall,
        .x86_16_interrupt,
        .x86_sysv,
        .x86_win,
        .x86_thiscall_mingw,
        .x86_64_x32,
        .aarch64_aapcs,
        .aarch64_aapcs_darwin,
        .aarch64_aapcs_win,
        .alpha_osf,
        .microblaze_std,
        .microblaze_interrupt,
        .mips64_n64,
        .mips64_n32,
        .mips_o32,
        .riscv64_lp64,
        .riscv32_ilp32,
        .sparc64_sysv,
        .sparc_sysv,
        .powerpc64_elf,
        .powerpc64_elf_altivec,
        .powerpc64_elf_v2,
        .powerpc_sysv,
        .powerpc_sysv_altivec,
        .powerpc_aix,
        .powerpc_aix_altivec,
        .wasm_mvp,
        .arc_sysv,
        .arc_interrupt,
        .avr_gnu,
        .bpf_std,
        .csky_sysv,
        .hexagon_sysv,
        .hexagon_sysv_hvx,
        .hppa_elf,
        .hppa64_elf,
        .kvx_lp64,
        .kvx_ilp32,
        .lanai_sysv,
        .loongarch64_lp64,
        .loongarch32_ilp32,
        .m68k_sysv,
        .m68k_gnu,
        .msp430_eabi,
        .or1k_sysv,
        .propeller_sysv,
        .s390x_sysv,
        .s390x_sysv_vx,
        .sh_gnu,
        .sh_renesas,
        .sh_interrupt,
        .ve_sysv,
        .xcore_xs1,
        .xcore_xs2,
        .xtensa_call0,
        .xtensa_windowed,
        .amdgcn_device,
        .spirv_device,
        .spirv_kernel,
        .spirv_fragment,
        .spirv_vertex,
        => null,
    };
}

/// Convert a zig-address space to an llvm address space.
pub fn toLlvmAddressSpace(address_space: std.builtin.AddressSpace, target: *const std.Target) Builder.AddrSpace {
    for (llvmAddrSpaceInfo(target)) |info| if (info.zig == address_space) return info.llvm;
    unreachable;
}

const AddrSpaceInfo = struct {
    zig: ?std.builtin.AddressSpace,
    llvm: Builder.AddrSpace,
    non_integral: bool = false,
    size: ?u16 = null,
    abi: ?u16 = null,
    pref: ?u16 = null,
    idx: ?u16 = null,
    force_in_data_layout: bool = false,
};
fn llvmAddrSpaceInfo(target: *const std.Target) []const AddrSpaceInfo {
    return switch (target.cpu.arch) {
        .x86, .x86_64 => &.{
            .{ .zig = .generic, .llvm = .default },
            .{ .zig = .gs, .llvm = Builder.AddrSpace.x86.gs },
            .{ .zig = .fs, .llvm = Builder.AddrSpace.x86.fs },
            .{ .zig = .ss, .llvm = Builder.AddrSpace.x86.ss },
            .{ .zig = null, .llvm = Builder.AddrSpace.x86.ptr32_sptr, .size = 32, .abi = 32, .force_in_data_layout = true },
            .{ .zig = null, .llvm = Builder.AddrSpace.x86.ptr32_uptr, .size = 32, .abi = 32, .force_in_data_layout = true },
            .{ .zig = null, .llvm = Builder.AddrSpace.x86.ptr64, .size = 64, .abi = 64, .force_in_data_layout = true },
        },
        .nvptx, .nvptx64 => &.{
            .{ .zig = .generic, .llvm = Builder.AddrSpace.nvptx.generic },
            .{ .zig = .global, .llvm = Builder.AddrSpace.nvptx.global },
            .{ .zig = .constant, .llvm = Builder.AddrSpace.nvptx.constant },
            .{ .zig = .param, .llvm = Builder.AddrSpace.nvptx.param },
            .{ .zig = .shared, .llvm = Builder.AddrSpace.nvptx.shared },
            .{ .zig = .local, .llvm = Builder.AddrSpace.nvptx.local },
        },
        .amdgcn => &.{
            .{ .zig = .generic, .llvm = Builder.AddrSpace.amdgpu.flat, .force_in_data_layout = true },
            .{ .zig = .global, .llvm = Builder.AddrSpace.amdgpu.global, .force_in_data_layout = true },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.region, .size = 32, .abi = 32 },
            .{ .zig = .shared, .llvm = Builder.AddrSpace.amdgpu.local, .size = 32, .abi = 32 },
            .{ .zig = .constant, .llvm = Builder.AddrSpace.amdgpu.constant, .force_in_data_layout = true },
            .{ .zig = .local, .llvm = Builder.AddrSpace.amdgpu.private, .size = 32, .abi = 32 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_32bit, .size = 32, .abi = 32 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.buffer_fat_pointer, .non_integral = true, .size = 160, .abi = 256, .idx = 32 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.buffer_resource, .non_integral = true, .size = 128, .abi = 128 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.buffer_strided_pointer, .non_integral = true, .size = 192, .abi = 256, .idx = 32 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_0 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_1 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_2 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_3 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_4 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_5 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_6 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_7 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_8 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_9 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_10 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_11 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_12 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_13 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_14 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.constant_buffer_15 },
            .{ .zig = null, .llvm = Builder.AddrSpace.amdgpu.streamout_register },
        },
        .avr => &.{
            .{ .zig = .generic, .llvm = Builder.AddrSpace.avr.data, .abi = 8 },
            .{ .zig = .flash, .llvm = Builder.AddrSpace.avr.program, .abi = 8 },
            .{ .zig = .flash1, .llvm = Builder.AddrSpace.avr.program1, .abi = 8 },
            .{ .zig = .flash2, .llvm = Builder.AddrSpace.avr.program2, .abi = 8 },
            .{ .zig = .flash3, .llvm = Builder.AddrSpace.avr.program3, .abi = 8 },
            .{ .zig = .flash4, .llvm = Builder.AddrSpace.avr.program4, .abi = 8 },
            .{ .zig = .flash5, .llvm = Builder.AddrSpace.avr.program5, .abi = 8 },
        },
        .wasm32, .wasm64 => &.{
            .{ .zig = .generic, .llvm = Builder.AddrSpace.wasm.default, .force_in_data_layout = true },
            .{ .zig = null, .llvm = Builder.AddrSpace.wasm.variable, .non_integral = true },
            .{ .zig = null, .llvm = Builder.AddrSpace.wasm.externref, .non_integral = true, .size = 8, .abi = 8 },
            .{ .zig = null, .llvm = Builder.AddrSpace.wasm.funcref, .non_integral = true, .size = 8, .abi = 8 },
        },
        .m68k => &.{
            .{ .zig = .generic, .llvm = .default, .abi = 16, .pref = 32 },
        },
        else => &.{
            .{ .zig = .generic, .llvm = .default },
        },
    };
}

/// On some targets, global values that are in the generic address space must be generated into a
/// different address space, and then cast back to the generic address space.
fn llvmDefaultGlobalAddressSpace(target: *const std.Target) Builder.AddrSpace {
    return switch (target.cpu.arch) {
        // On amdgcn, globals must be explicitly allocated and uploaded so that the program can access
        // them.
        .amdgcn => Builder.AddrSpace.amdgpu.global,
        else => .default,
    };
}

/// Return the actual address space that a value should be stored in if its a global address space.
/// When a value is placed in the resulting address space, it needs to be cast back into wanted_address_space.
fn toLlvmGlobalAddressSpace(wanted_address_space: std.builtin.AddressSpace, target: *const std.Target) Builder.AddrSpace {
    return switch (wanted_address_space) {
        .generic => llvmDefaultGlobalAddressSpace(target),
        else => |as| toLlvmAddressSpace(as, target),
    };
}

/// This function returns true if we expect LLVM to lower f16 correctly
/// and false if we expect LLVM to crash if it encounters an f16 type,
/// or if it produces miscompilations.
pub fn backendSupportsF16(target: *const std.Target) bool {
    return switch (target.cpu.arch) {
        // https://github.com/llvm/llvm-project/issues/97981
        .csky,
        // https://github.com/llvm/llvm-project/issues/97981
        .powerpc,
        .powerpcle,
        .powerpc64,
        .powerpc64le,
        // https://github.com/llvm/llvm-project/issues/97981
        .wasm32,
        .wasm64,
        // https://github.com/llvm/llvm-project/issues/97981
        .sparc,
        .sparc64,
        => false,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        => target.abi.float() == .soft or target.cpu.has(.arm, .fullfp16),
        else => true,
    };
}

/// This function returns true if we expect LLVM to lower x86_fp80 correctly
/// and false if we expect LLVM to crash if it encounters an x86_fp80 type,
/// or if it produces miscompilations.
pub fn backendSupportsF80(target: *const std.Target) bool {
    return switch (target.cpu.arch) {
        .x86, .x86_64 => !target.cpu.has(.x86, .soft_float),
        else => false,
    };
}

/// This function returns true if we expect LLVM to lower f128 correctly,
/// and false if we expect LLVM to crash if it encounters an f128 type,
/// or if it produces miscompilations.
pub fn backendSupportsF128(target: *const std.Target) bool {
    return switch (target.cpu.arch) {
        // https://github.com/llvm/llvm-project/issues/121122
        .amdgcn,
        // Test failures all over the place.
        .mips64,
        .mips64el,
        // https://github.com/llvm/llvm-project/issues/41838
        .sparc,
        => false,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        => target.abi.float() == .soft or target.cpu.has(.arm, .fp_armv8),
        else => true,
    };
}

/// We need to insert extra padding if LLVM's isn't enough.
/// However we don't want to ever call LLVMABIAlignmentOfType or
/// LLVMABISizeOfType because these functions will trip assertions
/// when using them for self-referential types. So our strategy is
/// to use non-packed llvm structs but to emit all padding explicitly.
/// We can do this because for all types, Zig ABI alignment >= LLVM ABI
/// alignment.
const struct_layout_version = 2;

// TODO: Restore the non_null field to i1 once
//       https://github.com/llvm/llvm-project/issues/56585/ is fixed
pub const optional_layout_version = 3;

pub fn initializeLLVMTarget(arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        .aarch64, .aarch64_be => {
            bindings.LLVMInitializeAArch64Target();
            bindings.LLVMInitializeAArch64TargetInfo();
            bindings.LLVMInitializeAArch64TargetMC();
            bindings.LLVMInitializeAArch64AsmPrinter();
            bindings.LLVMInitializeAArch64AsmParser();
        },
        .amdgcn => {
            bindings.LLVMInitializeAMDGPUTarget();
            bindings.LLVMInitializeAMDGPUTargetInfo();
            bindings.LLVMInitializeAMDGPUTargetMC();
            bindings.LLVMInitializeAMDGPUAsmPrinter();
            bindings.LLVMInitializeAMDGPUAsmParser();
        },
        .thumb, .thumbeb, .arm, .armeb => {
            bindings.LLVMInitializeARMTarget();
            bindings.LLVMInitializeARMTargetInfo();
            bindings.LLVMInitializeARMTargetMC();
            bindings.LLVMInitializeARMAsmPrinter();
            bindings.LLVMInitializeARMAsmParser();
        },
        .avr => {
            bindings.LLVMInitializeAVRTarget();
            bindings.LLVMInitializeAVRTargetInfo();
            bindings.LLVMInitializeAVRTargetMC();
            bindings.LLVMInitializeAVRAsmPrinter();
            bindings.LLVMInitializeAVRAsmParser();
        },
        .bpfel, .bpfeb => {
            bindings.LLVMInitializeBPFTarget();
            bindings.LLVMInitializeBPFTargetInfo();
            bindings.LLVMInitializeBPFTargetMC();
            bindings.LLVMInitializeBPFAsmPrinter();
            bindings.LLVMInitializeBPFAsmParser();
        },
        .hexagon => {
            bindings.LLVMInitializeHexagonTarget();
            bindings.LLVMInitializeHexagonTargetInfo();
            bindings.LLVMInitializeHexagonTargetMC();
            bindings.LLVMInitializeHexagonAsmPrinter();
            bindings.LLVMInitializeHexagonAsmParser();
        },
        .lanai => {
            bindings.LLVMInitializeLanaiTarget();
            bindings.LLVMInitializeLanaiTargetInfo();
            bindings.LLVMInitializeLanaiTargetMC();
            bindings.LLVMInitializeLanaiAsmPrinter();
            bindings.LLVMInitializeLanaiAsmParser();
        },
        .mips, .mipsel, .mips64, .mips64el => {
            bindings.LLVMInitializeMipsTarget();
            bindings.LLVMInitializeMipsTargetInfo();
            bindings.LLVMInitializeMipsTargetMC();
            bindings.LLVMInitializeMipsAsmPrinter();
            bindings.LLVMInitializeMipsAsmParser();
        },
        .msp430 => {
            bindings.LLVMInitializeMSP430Target();
            bindings.LLVMInitializeMSP430TargetInfo();
            bindings.LLVMInitializeMSP430TargetMC();
            bindings.LLVMInitializeMSP430AsmPrinter();
            bindings.LLVMInitializeMSP430AsmParser();
        },
        .nvptx, .nvptx64 => {
            bindings.LLVMInitializeNVPTXTarget();
            bindings.LLVMInitializeNVPTXTargetInfo();
            bindings.LLVMInitializeNVPTXTargetMC();
            bindings.LLVMInitializeNVPTXAsmPrinter();
            // There is no LLVMInitializeNVPTXAsmParser function available.
        },
        .powerpc, .powerpcle, .powerpc64, .powerpc64le => {
            bindings.LLVMInitializePowerPCTarget();
            bindings.LLVMInitializePowerPCTargetInfo();
            bindings.LLVMInitializePowerPCTargetMC();
            bindings.LLVMInitializePowerPCAsmPrinter();
            bindings.LLVMInitializePowerPCAsmParser();
        },
        .riscv32, .riscv32be, .riscv64, .riscv64be => {
            bindings.LLVMInitializeRISCVTarget();
            bindings.LLVMInitializeRISCVTargetInfo();
            bindings.LLVMInitializeRISCVTargetMC();
            bindings.LLVMInitializeRISCVAsmPrinter();
            bindings.LLVMInitializeRISCVAsmParser();
        },
        .sparc, .sparc64 => {
            bindings.LLVMInitializeSparcTarget();
            bindings.LLVMInitializeSparcTargetInfo();
            bindings.LLVMInitializeSparcTargetMC();
            bindings.LLVMInitializeSparcAsmPrinter();
            bindings.LLVMInitializeSparcAsmParser();
        },
        .s390x => {
            bindings.LLVMInitializeSystemZTarget();
            bindings.LLVMInitializeSystemZTargetInfo();
            bindings.LLVMInitializeSystemZTargetMC();
            bindings.LLVMInitializeSystemZAsmPrinter();
            bindings.LLVMInitializeSystemZAsmParser();
        },
        .wasm32, .wasm64 => {
            bindings.LLVMInitializeWebAssemblyTarget();
            bindings.LLVMInitializeWebAssemblyTargetInfo();
            bindings.LLVMInitializeWebAssemblyTargetMC();
            bindings.LLVMInitializeWebAssemblyAsmPrinter();
            bindings.LLVMInitializeWebAssemblyAsmParser();
        },
        .x86, .x86_64 => {
            bindings.LLVMInitializeX86Target();
            bindings.LLVMInitializeX86TargetInfo();
            bindings.LLVMInitializeX86TargetMC();
            bindings.LLVMInitializeX86AsmPrinter();
            bindings.LLVMInitializeX86AsmParser();
        },
        .xtensa => {
            if (build_options.llvm_has_xtensa) {
                bindings.LLVMInitializeXtensaTarget();
                bindings.LLVMInitializeXtensaTargetInfo();
                bindings.LLVMInitializeXtensaTargetMC();
                // There is no LLVMInitializeXtensaAsmPrinter function.
                bindings.LLVMInitializeXtensaAsmParser();
            }
        },
        .xcore => {
            bindings.LLVMInitializeXCoreTarget();
            bindings.LLVMInitializeXCoreTargetInfo();
            bindings.LLVMInitializeXCoreTargetMC();
            bindings.LLVMInitializeXCoreAsmPrinter();
            // There is no LLVMInitializeXCoreAsmParser function.
        },
        .m68k => {
            if (build_options.llvm_has_m68k) {
                bindings.LLVMInitializeM68kTarget();
                bindings.LLVMInitializeM68kTargetInfo();
                bindings.LLVMInitializeM68kTargetMC();
                bindings.LLVMInitializeM68kAsmPrinter();
                bindings.LLVMInitializeM68kAsmParser();
            }
        },
        .csky => {
            if (build_options.llvm_has_csky) {
                bindings.LLVMInitializeCSKYTarget();
                bindings.LLVMInitializeCSKYTargetInfo();
                bindings.LLVMInitializeCSKYTargetMC();
                // There is no LLVMInitializeCSKYAsmPrinter function.
                bindings.LLVMInitializeCSKYAsmParser();
            }
        },
        .ve => {
            bindings.LLVMInitializeVETarget();
            bindings.LLVMInitializeVETargetInfo();
            bindings.LLVMInitializeVETargetMC();
            bindings.LLVMInitializeVEAsmPrinter();
            bindings.LLVMInitializeVEAsmParser();
        },
        .arc => {
            if (build_options.llvm_has_arc) {
                bindings.LLVMInitializeARCTarget();
                bindings.LLVMInitializeARCTargetInfo();
                bindings.LLVMInitializeARCTargetMC();
                bindings.LLVMInitializeARCAsmPrinter();
                // There is no LLVMInitializeARCAsmParser function.
            }
        },
        .loongarch32, .loongarch64 => {
            bindings.LLVMInitializeLoongArchTarget();
            bindings.LLVMInitializeLoongArchTargetInfo();
            bindings.LLVMInitializeLoongArchTargetMC();
            bindings.LLVMInitializeLoongArchAsmPrinter();
            bindings.LLVMInitializeLoongArchAsmParser();
        },
        .spirv32,
        .spirv64,
        => {
            bindings.LLVMInitializeSPIRVTarget();
            bindings.LLVMInitializeSPIRVTargetInfo();
            bindings.LLVMInitializeSPIRVTargetMC();
            bindings.LLVMInitializeSPIRVAsmPrinter();
        },

        // LLVM does does not have a backend for these.
        .alpha,
        .arceb,
        .hppa,
        .hppa64,
        .kalimba,
        .kvx,
        .microblaze,
        .microblazeel,
        .or1k,
        .propeller,
        .sh,
        .sheb,
        .x86_16,
        .xtensaeb,
        => unreachable,
    }
}
