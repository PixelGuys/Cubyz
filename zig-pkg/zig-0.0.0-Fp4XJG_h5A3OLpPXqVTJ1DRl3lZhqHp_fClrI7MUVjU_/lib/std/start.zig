// This file is included in the compilation unit when exporting an executable.

const builtin = @import("builtin");
const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;
const is_wasm = native_arch.isWasm();

const std = @import("std.zig");
const assert = std.debug.assert;
const uefi = std.os.uefi;
const elf = std.elf;

const root = @import("root");

const start_sym_name = if (native_arch.isMIPS()) "__start" else "_start";

comptime {
    // No matter what, we import the root file, so that any export, test, comptime
    // decls there get run.
    _ = root;

    if (builtin.output_mode == .Lib and builtin.link_mode == .dynamic) {
        if (native_os == .windows and !@hasDecl(root, "_DllMainCRTStartup")) {
            @export(&_DllMainCRTStartup, .{ .name = "_DllMainCRTStartup" });
        }
    } else if (builtin.output_mode == .Exe or @hasDecl(root, "main")) {
        if (builtin.link_libc and @hasDecl(root, "main")) {
            if (is_wasm) {
                @export(&mainWithoutEnv, .{ .name = "__main_argc_argv" });
            } else if (!@typeInfo(@TypeOf(root.main)).@"fn".calling_convention.eql(.c)) {
                @export(&main, .{ .name = "main" });
            }
        } else if (native_os == .windows and builtin.link_libc and @hasDecl(root, "wWinMain")) {
            if (!@typeInfo(@TypeOf(root.wWinMain)).@"fn".calling_convention.eql(.c)) {
                @export(&wWinMain, .{ .name = "wWinMain" });
            }
        } else if (native_os == .windows) {
            if (!@hasDecl(root, "WinMain") and !@hasDecl(root, "WinMainCRTStartup") and
                !@hasDecl(root, "wWinMain") and !@hasDecl(root, "wWinMainCRTStartup"))
            {
                @export(&WinStartup, .{ .name = "wWinMainCRTStartup" });
            } else if (@hasDecl(root, "WinMain") and !@hasDecl(root, "WinMainCRTStartup") and
                !@hasDecl(root, "wWinMain") and !@hasDecl(root, "wWinMainCRTStartup"))
            {
                @compileError("WinMain not supported; declare wWinMain or main instead");
            } else if (@hasDecl(root, "wWinMain") and !@hasDecl(root, "wWinMainCRTStartup") and
                !@hasDecl(root, "WinMain") and !@hasDecl(root, "WinMainCRTStartup"))
            {
                @export(&wWinMainCRTStartup, .{ .name = "wWinMainCRTStartup" });
            }
        } else if (native_os == .uefi) {
            if (!@hasDecl(root, "EfiMain")) @export(&EfiMain, .{ .name = "EfiMain" });
        } else if (native_os == .wasi) {
            const wasm_start_sym = switch (builtin.wasi_exec_model) {
                .reactor => "_initialize",
                .command => "_start",
            };
            if (!@hasDecl(root, wasm_start_sym) and @hasDecl(root, "main")) {
                // Only call main when defined. For WebAssembly it's allowed to pass `-fno-entry` in which
                // case it's not required to provide an entrypoint such as main.
                @export(&startWasi, .{ .name = wasm_start_sym });
            }
        } else if (is_wasm and native_os == .freestanding) {
            // Only call main when defined. For WebAssembly it's allowed to pass `-fno-entry` in which
            // case it's not required to provide an entrypoint such as main.
            if (!@hasDecl(root, start_sym_name) and @hasDecl(root, "main")) @export(&wasm_freestanding_start, .{ .name = start_sym_name });
        } else switch (native_os) {
            .other, .freestanding, .@"3ds", .psp, .vita => {},
            else => if (!@hasDecl(root, start_sym_name)) @export(&_start, .{ .name = start_sym_name }),
        }
    }
}

fn _DllMainCRTStartup(
    hinstDLL: std.os.windows.HINSTANCE,
    fdwReason: std.os.windows.DWORD,
    lpReserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL {
    if (!builtin.single_threaded and !builtin.link_libc) {
        _ = @import("os/windows/tls.zig");
    }

    if (@hasDecl(root, "DllMain")) {
        return root.DllMain(hinstDLL, fdwReason, lpReserved);
    }

    return .TRUE;
}

fn wasm_freestanding_start() callconv(.c) void {
    // This is marked inline because for some reason LLVM in
    // release mode fails to inline it, and we want fewer call frames in stack traces.
    _ = @call(.always_inline, callMain, .{ {}, std.process.Environ.Block.global });
}

fn startWasi() callconv(.c) void {
    // The function call is marked inline because for some reason LLVM in
    // release mode fails to inline it, and we want fewer call frames in stack traces.
    switch (builtin.wasi_exec_model) {
        .reactor => _ = @call(.always_inline, callMain, .{ {}, std.process.Environ.Block.global }),
        .command => std.os.wasi.proc_exit(@call(.always_inline, callMain, .{ {}, std.process.Environ.Block.global })),
    }
}

fn EfiMain(handle: uefi.Handle, system_table: *uefi.tables.SystemTable) callconv(.c) usize {
    uefi.handle = handle;
    uefi.system_table = system_table;

    switch (@typeInfo(@TypeOf(root.main)).@"fn".return_type.?) {
        noreturn => {
            root.main();
        },
        void => {
            root.main();
            return 0;
        },
        uefi.Status => {
            return @intFromEnum(root.main());
        },
        uefi.Error!void => {
            root.main() catch |err| switch (err) {
                error.Unexpected => @panic("EfiMain: unexpected error"),
                else => {
                    const status = uefi.Status.fromError(@errorCast(err));
                    return @intFromEnum(status);
                },
            };

            return 0;
        },
        else => @compileError(
            "expected return type of main to be 'void', 'noreturn', " ++
                "'uefi.Status', or 'uefi.Error!void'",
        ),
    }
}

fn _start() callconv(.naked) noreturn {
    // TODO set Top of Stack on non x86_64-plan9
    if (native_os == .plan9 and native_arch == .x86_64) {
        // from /sys/src/libc/amd64/main9.s
        std.os.plan9.tos = asm volatile (""
            : [tos] "={rax}" (-> *std.os.plan9.Tos),
        );
    }

    // This is the first userspace frame. Prevent DWARF-based unwinders from unwinding further. We
    // prevent FP-based unwinders from unwinding further by zeroing the register below.
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (switch (native_arch) {
            .aarch64, .aarch64_be => ".cfi_undefined lr",
            .alpha => ".cfi_undefined $26",
            .arc, .arceb => ".cfi_undefined blink",
            .arm, .armeb, .thumb, .thumbeb => "", // https://github.com/llvm/llvm-project/issues/115891
            .csky => ".cfi_undefined lr",
            .hexagon => ".cfi_undefined r31",
            .kvx => ".cfi_undefined r14",
            .loongarch32, .loongarch64 => ".cfi_undefined 1",
            .m68k => ".cfi_undefined %%pc",
            .microblaze, .microblazeel => ".cfi_undefined r15",
            .mips, .mipsel, .mips64, .mips64el => ".cfi_undefined $ra",
            .or1k => ".cfi_undefined r9",
            .powerpc, .powerpcle, .powerpc64, .powerpc64le => ".cfi_undefined lr",
            .riscv32, .riscv32be, .riscv64, .riscv64be => if (builtin.zig_backend == .stage2_riscv64)
                ""
            else
                ".cfi_undefined ra",
            .s390x => ".cfi_undefined %%r14",
            .sh, .sheb => ".cfi_undefined pr",
            .sparc, .sparc64 => ".cfi_undefined %%i7",
            .x86 => ".cfi_undefined %%eip",
            .x86_64 => ".cfi_undefined %%rip",
            else => @compileError("unsupported arch"),
        });

    // Move this to the riscv prong below when this is resolved: https://github.com/ziglang/zig/issues/20918
    if (builtin.cpu.arch.isRISCV() and builtin.zig_backend != .stage2_riscv64) asm volatile (
        \\ .weak __global_pointer$
        \\ .hidden __global_pointer$
        \\ .option push
        \\ .option norelax
        \\ lla gp, __global_pointer$
        \\ .option pop
    );

    // Note that we maintain a very low level of trust with regards to ABI guarantees at this point.
    // We will redundantly align the stack, clear the link register, etc. While e.g. the Linux
    // kernel is usually good about upholding the ABI guarantees, the same cannot be said of dynamic
    // linkers; musl's ldso, for example, opts to not align the stack when invoking the dynamic
    // linker explicitly.
    asm volatile (switch (native_arch) {
            .x86_64 =>
            \\ xorl %%ebp, %%ebp
            \\ movq %%rsp, %%rdi
            \\ andq $-16, %%rsp
            \\ callq %[posixCallMainAndExit:P]
            ,
            .x86 =>
            \\ xorl %%ebp, %%ebp
            \\ movl %%esp, %%eax
            \\ andl $-16, %%esp
            \\ subl $12, %%esp
            \\ pushl %%eax
            \\ calll %[posixCallMainAndExit:P]
            ,
            .aarch64, .aarch64_be =>
            \\ mov fp, #0
            \\ mov lr, #0
            \\ mov x0, sp
            \\ and sp, x0, #-16
            \\ b %[posixCallMainAndExit]
            ,
            .alpha =>
            // $15 = FP, $26 = LR, $29 = GP, $30 = SP
            \\ br $29, 1f
            \\1:
            \\ ldgp $29, 0($29)
            \\ mov 0, $15
            \\ mov 0, $26
            \\ mov $30, $16
            \\ ldi $1, -16
            \\ and $30, $30, $1
            \\ jsr $26, %[posixCallMainAndExit]
            ,
            .arc, .arceb =>
            // ARC v1 and v2 had a very low stack alignment requirement of 4; v3 increased it to 16.
            \\ mov fp, 0
            \\ mov blink, 0
            \\ mov r0, sp
            \\ and sp, sp, -16
            \\ b %[posixCallMainAndExit]
            ,
            .arm, .armeb, .thumb, .thumbeb =>
            // Note that this code must work for Thumb-1.
            // r7 = FP (local), r11 = FP (unwind)
            \\ movs v1, #0
            \\ mov r7, v1
            \\ mov r11, v1
            \\ mov lr, v1
            \\ mov a1, sp
            \\ subs v1, #16
            \\ ands v1, a1
            \\ mov sp, v1
            \\ b %[posixCallMainAndExit]
            ,
            .csky =>
            // The CSKY ABI assumes that `gb` is set to the address of the GOT in order for
            // position-independent code to work. We depend on this in `std.pie` to locate
            // `_DYNAMIC` as well.
            // r8 = FP
            \\ grs t0, 1f
            \\ 1:
            \\ lrw gb, 1b@GOTPC
            \\ addu gb, t0
            \\ movi r8, 0
            \\ movi lr, 0
            \\ mov a0, sp
            \\ andi sp, sp, -8
            \\ jmpi %[posixCallMainAndExit]
            ,
            .hexagon =>
            // r29 = SP, r30 = FP, r31 = LR
            \\ r30 = #0
            \\ r31 = #0
            \\ r0 = r29
            \\ r29 = and(r29, #-8)
            \\ memw(r29 + #-8) = r29
            \\ r29 = add(r29, #-8)
            \\ call %[posixCallMainAndExit]
            ,
            .kvx =>
            \\ make $fp = 0
            \\ ;;
            \\ set $ra = $fp
            \\ copyd $r0 = $sp
            \\ andd $sp = $sp, -32
            \\ ;;
            \\ goto %[posixCallMainAndExit]
            ,
            .loongarch32 =>
            \\ move $fp, $zero
            \\ move $ra, $zero
            \\ move $a0, $sp
            \\ srli.w $sp, $sp, 4
            \\ slli.w $sp, $sp, 4
            \\ b %[posixCallMainAndExit]
            ,
            .loongarch64 =>
            \\ move $fp, $zero
            \\ move $ra, $zero
            \\ move $a0, $sp
            \\ bstrins.d $sp, $zero, 3, 0
            \\ b %[posixCallMainAndExit]
            ,
            .or1k =>
            // r1 = SP, r2 = FP, r9 = LR
            \\ l.ori r2, r0, 0
            \\ l.ori r9, r0, 0
            \\ l.ori r3, r1, 0
            \\ l.andi r1, r1, -4
            \\ l.jal %[posixCallMainAndExit]
            ,
            .riscv32, .riscv32be, .riscv64, .riscv64be =>
            \\ li fp, 0
            \\ li ra, 0
            \\ mv a0, sp
            \\ andi sp, sp, -16
            \\ tail %[posixCallMainAndExit]@plt
            ,
            .m68k =>
            // Note that the - 8 is needed because pc in the jsr instruction points into the middle
            // of the jsr instruction. (The lea is 6 bytes, the jsr is 4 bytes.)
            \\ suba.l %%fp, %%fp
            \\ move.l %%sp, %%a0
            \\ move.l %%a0, %%d0
            \\ and.l #-4, %%d0
            \\ move.l %%d0, %%sp
            \\ move.l %%a0, -(%%sp)
            \\ lea %[posixCallMainAndExit] - . - 8, %%a0
            \\ jsr (%%pc, %%a0)
            ,
            .microblaze, .microblazeel =>
            // r1 = SP, r15 = LR, r19 = FP, r20 = GP
            \\ ori r15, r0, r0
            \\ ori r19, r0, r0
            \\ mfs r20, rpc
            \\ addik r20, r20, _GLOBAL_OFFSET_TABLE_ + 8
            \\ ori r5, r1, r0
            \\ andi r1, r1, -4
            \\ brlid r15, %[posixCallMainAndExit]
            ,
            .mips, .mipsel =>
            \\ move $fp, $zero
            \\ bal 1f
            \\ .gpword .
            \\ .gpword %[posixCallMainAndExit]
            \\1:
            // The `gp` register on MIPS serves a similar purpose to `r2` (ToC pointer) on PPC64.
            \\ lw $gp, 0($ra)
            \\ nop
            \\ subu $gp, $ra, $gp
            \\ lw $t9, 4($ra)
            \\ nop
            \\ addu $t9, $t9, $gp
            \\ move $ra, $zero
            \\ move $a0, $sp
            \\ and $sp, -8
            \\ subu $sp, $sp, 16
            \\ jalr $t9
            ,
            .mips64, .mips64el => switch (builtin.abi) {
                .gnuabin32, .muslabin32 =>
                \\ move $fp, $zero
                \\ bal 1f
                \\ .gpword .
                \\ .gpword %[posixCallMainAndExit]
                \\1:
                // The `gp` register on MIPS serves a similar purpose to `r2` (ToC pointer) on PPC64.
                \\ lw $gp, 0($ra)
                \\ subu $gp, $ra, $gp
                \\ lw $t9, 4($ra)
                \\ addu $t9, $t9, $gp
                \\ move $ra, $zero
                \\ move $a0, $sp
                \\ and $sp, -8
                \\ subu $sp, $sp, 16
                \\ jalr $t9
                ,
                else =>
                \\ move $fp, $zero
                // This is needed because early MIPS versions don't support misaligned loads. Without
                // this directive, the hidden `nop` inserted to fill the delay slot after `bal` would
                // cause the two doublewords to be aligned to 4 bytes instead of 8.
                \\ .balign 8
                \\ bal 1f
                \\ .gpdword .
                \\ .gpdword %[posixCallMainAndExit]
                \\1:
                // The `gp` register on MIPS serves a similar purpose to `r2` (ToC pointer) on PPC64.
                \\ ld $gp, 0($ra)
                \\ dsubu $gp, $ra, $gp
                \\ ld $t9, 8($ra)
                \\ daddu $t9, $t9, $gp
                \\ move $ra, $zero
                \\ move $a0, $sp
                \\ and $sp, -16
                \\ dsubu $sp, $sp, 16
                \\ jalr $t9
                ,
            },
            .powerpc, .powerpcle =>
            // Set up the initial stack frame, and clear the back chain pointer.
            // r1 = SP, r31 = FP
            \\ mr 3, 1
            \\ clrrwi 1, 1, 4
            \\ li 0, 0
            \\ stwu 1, -16(1)
            \\ stw 0, 0(1)
            \\ li 31, 0
            \\ mtlr 0
            \\ b %[posixCallMainAndExit]
            ,
            .powerpc64, .powerpc64le =>
            // Set up the ToC and initial stack frame, and clear the back chain pointer.
            // r1 = SP, r2 = ToC, r31 = FP
            \\ addis 2, 12, .TOC. - %[_start]@ha
            \\ addi 2, 2, .TOC. - %[_start]@l
            \\ mr 3, 1
            \\ clrrdi 1, 1, 4
            \\ li 0, 0
            \\ stdu 0, -32(1)
            \\ li 31, 0
            \\ mtlr 0
            \\ b %[posixCallMainAndExit]
            \\ nop
            ,
            .s390x =>
            // Set up the stack frame (register save area and cleared back-chain slot).
            // r11 = FP, r14 = LR, r15 = SP
            \\ lghi %%r11, 0
            \\ lghi %%r14, 0
            \\ lgr %%r2, %%r15
            \\ lghi %%r0, -16
            \\ ngr %%r15, %%r0
            \\ aghi %%r15, -160
            \\ lghi %%r0, 0
            \\ stg  %%r0, 0(%%r15)
            \\ jg %[posixCallMainAndExit]
            ,
            .sh, .sheb =>
            // r14 = FP, r15 = SP, pr = LR
            \\ mov #0, r0
            \\ lds r0, pr
            \\ mov r0, r14
            \\ mov r15, r4
            \\ mov #-4, r0
            \\ and r0, r15
            \\ mov.l 2f, r1
            \\1:
            \\ bsrf r1
            \\2:
            \\ .balign 4
            \\ .long %[posixCallMainAndExit]@PCREL - (1b + 4 - .)
            ,
            .sparc =>
            // argc is stored after a register window (16 registers * 4 bytes).
            // i7 = LR
            \\ mov %%g0, %%fp
            \\ mov %%g0, %%i7
            \\ add %%sp, 64, %%o0
            \\ and %%sp, -8, %%sp
            \\ ba,a %[posixCallMainAndExit]
            ,
            .sparc64 =>
            // argc is stored after a register window (16 registers * 8 bytes) plus the stack bias
            // (2047 bytes).
            // i7 = LR
            \\ mov %%g0, %%fp
            \\ mov %%g0, %%i7
            \\ add %%sp, 2175, %%o0
            \\ add %%sp, 2047, %%sp
            \\ and %%sp, -16, %%sp
            \\ sub %%sp, 2047, %%sp
            \\ ba,a %[posixCallMainAndExit]
            ,
            else => @compileError("unsupported arch"),
        }
        :
        : [_start] "X" (&_start),
          [posixCallMainAndExit] "X" (&posixCallMainAndExit),
    );
}

fn WinStartup() callconv(.withStackAlign(.c, 1)) noreturn {
    // Switch from the x87 fpu state set by windows to the state expected by the gnu abi.
    if (builtin.cpu.arch.isX86() and builtin.abi == .gnu) asm volatile ("fninit");

    if (!builtin.single_threaded and !builtin.link_libc) {
        _ = @import("os/windows/tls.zig");
    }

    std.Thread.maybeAttachSignalStack();
    std.debug.maybeEnableSegfaultHandler();

    std.os.windows.ntdll.RtlExitUserProcess(
        callMain(std.os.windows.peb().ProcessParameters.CommandLine.slice(), .global),
    );
}

fn wWinMainCRTStartup() callconv(.withStackAlign(.c, 1)) noreturn {
    // Switch from the x87 fpu state set by windows to the state expected by the gnu abi.
    if (builtin.cpu.arch.isX86() and builtin.abi == .gnu) asm volatile ("fninit");

    if (!builtin.single_threaded and !builtin.link_libc) {
        _ = @import("os/windows/tls.zig");
    }

    std.Thread.maybeAttachSignalStack();
    std.debug.maybeEnableSegfaultHandler();

    const result: std.os.windows.INT = call_wWinMain();
    std.os.windows.ntdll.RtlExitUserProcess(@as(std.os.windows.UINT, @bitCast(result)));
}

fn wWinMain(hInstance: *anyopaque, hPrevInstance: ?*anyopaque, pCmdLine: [*:0]u16, nCmdShow: c_int) callconv(.c) c_int {
    return root.wWinMain(@ptrCast(hInstance), @ptrCast(hPrevInstance), pCmdLine, @intCast(nCmdShow));
}

fn posixCallMainAndExit(argc_argv_ptr: [*]usize) callconv(.c) noreturn {
    // We're not ready to panic until thread local storage is initialized.
    @setRuntimeSafety(false);
    // Code coverage instrumentation might try to use thread local variables.
    @disableInstrumentation();
    const argc = argc_argv_ptr[0];
    const argv: [*][*:0]u8 = @ptrCast(argc_argv_ptr + 1);

    const envp_optional: [*:null]?[*:0]u8 = @ptrCast(@alignCast(argv + argc + 1));
    var envp_count: usize = 0;
    while (envp_optional[envp_count]) |_| : (envp_count += 1) {}
    const envp = envp_optional[0..envp_count :null];

    // Find the beginning of the auxiliary vector
    const auxv: [*]elf.Auxv = @ptrCast(@alignCast(envp.ptr + envp_count + 1));

    var at_hwcap: usize = 0;
    const phdrs = init: {
        var i: usize = 0;
        var at_phdr: usize = 0;
        var at_phnum: usize = 0;
        while (auxv[i].a_type != elf.AT_NULL) : (i += 1) {
            switch (auxv[i].a_type) {
                elf.AT_PHNUM => at_phnum = auxv[i].a_un.a_val,
                elf.AT_PHDR => at_phdr = auxv[i].a_un.a_val,
                elf.AT_HWCAP => at_hwcap = auxv[i].a_un.a_val,
                else => continue,
            }
        }
        break :init @as([*]elf.Phdr, @ptrFromInt(at_phdr))[0..at_phnum];
    };

    // Apply the initial relocations as early as possible in the startup process. We cannot
    // make calls yet on some architectures (e.g. MIPS) *because* they haven't been applied yet,
    // so this must be fully inlined.
    if (builtin.link_mode == .static and builtin.position_independent_executable) {
        @call(.always_inline, std.pie.relocate, .{phdrs});
    }

    if (native_os == .linux) {
        // This must be done after PIE relocations have been applied or we may crash
        // while trying to access the global variable (happens on MIPS at least).
        std.os.linux.elf_aux_maybe = auxv;

        if (!builtin.single_threaded) {
            // ARMv6 targets (and earlier) have no support for TLS in hardware.
            // FIXME: Elide the check for targets >= ARMv7 when the target feature API
            // becomes less verbose (and more usable).
            if (comptime native_arch.isArm()) {
                if (at_hwcap & std.os.linux.HWCAP.TLS == 0) {
                    // FIXME: Make __aeabi_read_tp call the kernel helper kuser_get_tls
                    // For the time being use a simple trap instead of a @panic call to
                    // keep the binary bloat under control.
                    @trap();
                }
            }

            // Initialize the TLS area.
            std.os.linux.tls.initStatic(phdrs);
        }

        // The way Linux executables represent stack size is via the PT_GNU_STACK
        // program header. However the kernel does not recognize it; it always gives 8 MiB.
        // Here we look for the stack size in our program headers and use setrlimit
        // to ask for more stack space.
        expandStackSize(phdrs);
    }

    const opt_init_array_start = @extern([*]const *const fn () callconv(.c) void, .{
        .name = "__init_array_start",
        .linkage = .weak,
    });
    const opt_init_array_end = @extern([*]const *const fn () callconv(.c) void, .{
        .name = "__init_array_end",
        .linkage = .weak,
    });
    if (opt_init_array_start) |init_array_start| {
        const init_array_end = opt_init_array_end.?;
        const slice = init_array_start[0 .. init_array_end - init_array_start];
        for (slice) |func| func();
    }

    std.process.exit(callMainWithArgs(argc, argv, envp));
}

fn expandStackSize(phdrs: []elf.Phdr) void {
    @disableInstrumentation();
    for (phdrs) |*phdr| {
        switch (phdr.p_type) {
            elf.PT_GNU_STACK => {
                if (phdr.p_memsz == 0) break;
                assert(phdr.p_memsz % std.heap.page_size_min == 0);

                // Silently fail if we are unable to get limits.
                const limits = std.posix.getrlimit(.STACK) catch break;

                // Clamp to limits.max .
                const wanted_stack_size = @min(phdr.p_memsz, limits.max);

                if (wanted_stack_size > limits.cur) {
                    std.posix.setrlimit(.STACK, .{
                        .cur = wanted_stack_size,
                        .max = limits.max,
                    }) catch {
                        // Because we could not increase the stack size to the upper bound,
                        // depending on what happens at runtime, a stack overflow may occur.
                        // However it would cause a segmentation fault, thanks to stack probing,
                        // so we do not have a memory safety issue here.
                        // This is intentional silent failure.
                        // This logic should be revisited when the following issues are addressed:
                        // https://github.com/ziglang/zig/issues/157
                        // https://github.com/ziglang/zig/issues/1006
                    };
                }
                break;
            },
            else => {},
        }
    }
}

inline fn callMainWithArgs(argc: usize, argv: [*][*:0]u8, envp: [:null]?[*:0]u8) u8 {
    const env_block: std.process.Environ.Block = .{ .slice = envp };
    if (std.Options.debug_threaded_io) |t| {
        if (@sizeOf(std.Io.Threaded.Argv0) != 0) t.argv0.value = argv[0];
        t.environ = .{ .process_environ = .{ .block = env_block } };
        t.environ_initialized = env_block.isEmpty();
    }
    std.Thread.maybeAttachSignalStack();
    std.debug.maybeEnableSegfaultHandler();
    return callMain(argv[0..argc], env_block);
}

fn main(c_argc: c_int, c_argv: [*][*:0]c_char, c_envp: [*:null]?[*:0]c_char) callconv(.c) c_int {
    var env_count: usize = 0;
    while (c_envp[env_count] != null) : (env_count += 1) {}
    const envp = c_envp[0..env_count :null];

    switch (builtin.os.tag) {
        .linux => {
            const at_phdr = std.c.getauxval(elf.AT_PHDR);
            const at_phnum = std.c.getauxval(elf.AT_PHNUM);
            const phdrs = (@as([*]elf.Phdr, @ptrFromInt(at_phdr)))[0..at_phnum];
            expandStackSize(phdrs);
        },
        .windows => {
            // On Windows, we ignore libc environment and argv and get those
            // values in their intended encoding from the PEB instead.
            std.Thread.maybeAttachSignalStack();
            std.debug.maybeEnableSegfaultHandler();
            return callMain(std.os.windows.peb().ProcessParameters.CommandLine.slice(), .global);
        },
        else => {},
    }

    return callMainWithArgs(@as(usize, @intCast(c_argc)), @as([*][*:0]u8, @ptrCast(c_argv)), @ptrCast(envp));
}

fn mainWithoutEnv(c_argc: c_int, c_argv: [*][*:0]c_char) callconv(.c) c_int {
    const argv = @as([*][*:0]u8, @ptrCast(c_argv))[0..@intCast(c_argc)];
    const environ: [:null]?[*:0]u8 = switch (builtin.os.tag) {
        .wasi, .emscripten => environ: {
            const c_environ = std.c.environ;
            var env_count: usize = 0;
            while (c_environ[env_count] != null) : (env_count += 1) {}
            break :environ c_environ[0..env_count :null];
        },
        else => &.{},
    };
    const env_block: std.process.Environ.Block = .{ .slice = environ };
    if (std.Options.debug_threaded_io) |t| {
        if (@sizeOf(std.Io.Threaded.Argv0) != 0) t.argv0.value = argv[0];
        t.environ = .{ .process_environ = .{ .block = env_block } };
        t.environ_initialized = env_block.isEmpty();
    }
    return callMain(argv, env_block);
}

/// General error message for a malformed return type
const bad_main_ret = "expected return type of main to be 'void', '!void', 'noreturn', 'u8', or '!u8'";

const use_debug_allocator = !is_wasm and switch (builtin.mode) {
    .Debug => true,
    .ReleaseSafe => !builtin.link_libc, // Not ideal, but the best we have for now.
    .ReleaseFast, .ReleaseSmall => !builtin.link_libc and builtin.single_threaded, // Also not ideal.
};
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

inline fn callMain(args: std.process.Args.Vector, environ: std.process.Environ.Block) u8 {
    const fn_info = @typeInfo(@TypeOf(root.main)).@"fn";
    if (fn_info.params.len == 0) return wrapMain(root.main());
    if (fn_info.params[0].type.? == std.process.Init.Minimal) return wrapMain(root.main(.{
        .args = .{ .vector = args },
        .environ = .{ .block = environ },
    }));

    const gpa = if (use_debug_allocator)
        debug_allocator.allocator()
    else if (builtin.link_libc)
        std.heap.c_allocator
    else if (is_wasm)
        std.heap.wasm_allocator
    else if (!builtin.single_threaded)
        std.heap.smp_allocator
    else
        comptime unreachable;

    defer if (use_debug_allocator) {
        _ = debug_allocator.deinit(); // Leaks do not affect return code.
    };

    const arena_backing_allocator = if (is_wasm) gpa else std.heap.page_allocator;

    var arena_allocator = std.heap.ArenaAllocator.init(arena_backing_allocator);
    defer arena_allocator.deinit();

    var threaded: std.Io.Threaded = .init(gpa, .{
        .argv0 = .init(.{ .vector = args }),
        .environ = .{ .block = environ },
    });
    defer threaded.deinit();

    var environ_map = std.process.Environ.createMap(.{ .block = environ }, gpa) catch |err|
        std.process.fatal("failed to parse environment variables: {t}", .{err});
    defer environ_map.deinit();

    const preopens = std.process.Preopens.init(arena_allocator.allocator()) catch |err|
        std.process.fatal("failed to init preopens: {t}", .{err});

    return wrapMain(root.main(.{
        .minimal = .{
            .args = .{ .vector = args },
            .environ = .{ .block = environ },
        },
        .arena = &arena_allocator,
        .gpa = gpa,
        .io = threaded.io(),
        .environ_map = &environ_map,
        .preopens = preopens,
    }));
}

inline fn wrapMain(result: anytype) u8 {
    const ReturnType = @TypeOf(result);
    switch (ReturnType) {
        void => return 0,
        noreturn => unreachable,
        u8 => return result,
        else => {},
    }
    if (@typeInfo(ReturnType) != .error_union) @compileError(bad_main_ret);

    const unwrapped_result = result catch |err| {
        std.log.err("{t}", .{err});
        switch (native_os) {
            .freestanding, .other => {},
            else => if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace),
        }
        return 1;
    };

    return switch (@TypeOf(unwrapped_result)) {
        noreturn => unreachable,
        void => 0,
        u8 => unwrapped_result,
        else => @compileError(bad_main_ret),
    };
}

fn call_wWinMain() std.os.windows.INT {
    const peb = std.os.windows.peb();
    const MAIN_HINSTANCE = @typeInfo(@TypeOf(root.wWinMain)).@"fn".params[0].type.?;
    const hInstance: MAIN_HINSTANCE = @ptrCast(peb.ImageBaseAddress);
    const lpCmdLine: [*:0]u16 = @ptrCast(peb.ProcessParameters.CommandLine.Buffer);

    // There are various types used for the 'show window' variable through the Win32 APIs:
    // - u16 in STARTUPINFOA.wShowWindow / STARTUPINFOW.wShowWindow
    // - c_int in ShowWindow
    // - u32 in PEB.ProcessParameters.dwShowWindow
    // Since STARTUPINFO is the bottleneck for the allowed values, we use `u16` as the
    // type which can coerce into i32/c_int/u32 depending on how the user defines their wWinMain
    // (the Win32 docs show wWinMain with `int` as the type for nShowCmd).
    const nShowCmd: u16 = nShowCmd: {
        // This makes Zig match the nShowCmd behavior of a C program with a WinMain symbol:
        // - With STARTF_USESHOWWINDOW set in STARTUPINFO.dwFlags of the CreateProcess call:
        //   - nShowCmd is STARTUPINFO.wShowWindow from the parent CreateProcess call
        // - With STARTF_USESHOWWINDOW unset:
        //   - nShowCmd is always SW_SHOWDEFAULT
        const SW_SHOWDEFAULT = 10;
        if (peb.ProcessParameters.dwFlags & std.os.windows.STARTF_USESHOWWINDOW != 0) {
            break :nShowCmd @truncate(peb.ProcessParameters.dwShowWindow);
        }
        break :nShowCmd SW_SHOWDEFAULT;
    };

    // second parameter hPrevInstance, MSDN: "This parameter is always NULL"
    return root.wWinMain(hInstance, null, lpCmdLine, nShowCmd);
}
