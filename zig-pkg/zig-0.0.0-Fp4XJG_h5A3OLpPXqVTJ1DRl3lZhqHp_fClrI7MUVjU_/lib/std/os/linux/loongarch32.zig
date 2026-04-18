const builtin = @import("builtin");
const std = @import("../../std.zig");
const SYS = std.os.linux.SYS;

pub fn syscall0(number: SYS) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall1(number: SYS, arg1: u32) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall2(number: SYS, arg1: u32, arg2: u32) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
          [arg2] "{$r5}" (arg2),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall3(number: SYS, arg1: u32, arg2: u32, arg3: u32) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
          [arg2] "{$r5}" (arg2),
          [arg3] "{$r6}" (arg3),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall4(number: SYS, arg1: u32, arg2: u32, arg3: u32, arg4: u32) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
          [arg2] "{$r5}" (arg2),
          [arg3] "{$r6}" (arg3),
          [arg4] "{$r7}" (arg4),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall5(number: SYS, arg1: u32, arg2: u32, arg3: u32, arg4: u32, arg5: u32) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
          [arg2] "{$r5}" (arg2),
          [arg3] "{$r6}" (arg3),
          [arg4] "{$r7}" (arg4),
          [arg5] "{$r8}" (arg5),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

pub fn syscall6(
    number: SYS,
    arg1: u32,
    arg2: u32,
    arg3: u32,
    arg4: u32,
    arg5: u32,
    arg6: u32,
) u32 {
    return asm volatile (
        \\ syscall 0
        : [ret] "={$r4}" (-> u32),
        : [number] "{$r11}" (@intFromEnum(number)),
          [arg1] "{$r4}" (arg1),
          [arg2] "{$r5}" (arg2),
          [arg3] "{$r6}" (arg3),
          [arg4] "{$r7}" (arg4),
          [arg5] "{$r8}" (arg5),
          [arg6] "{$r9}" (arg6),
        : .{ .r12 = true, .r13 = true, .r14 = true, .r15 = true, .r16 = true, .r17 = true, .r18 = true, .r19 = true, .r20 = true, .memory = true });
}

// FIXME
pub fn clone() callconv(.naked) u32 {
    // __clone(func, stack, flags, arg, ptid, tls, ctid)
    //           a0,    a1,    a2,  a3,   a4,  a5,   a6
    // sys_clone(flags, stack, ptid, ctid, tls)
    //              a0,    a1,   a2,   a3,  a4
    asm volatile (
        \\ srli.w $a1, $a1, 4
        \\ slli.w $a1, $a1, 4
        \\
        \\ # Save function pointer and argument pointer on new thread stack
        \\ addi.w  $a1, $a1, -16
        \\ st.w    $a0, $a1, 0     # save function pointer
        \\ st.w    $a3, $a1, 4     # save argument pointer
        \\ or      $a0, $a2, $zero
        \\ or      $a2, $a4, $zero
        \\ or      $a3, $a6, $zero
        \\ or      $a4, $a5, $zero
        \\ ori     $a7, $zero, 220 # SYS_clone
        \\ syscall 0
        \\
        \\ beq     $a0, $zero, 1f
        \\ jirl    $zero, $ra, 0
        \\1:
    );
    if (builtin.unwind_tables != .none or !builtin.strip_debug_info) asm volatile (
        \\ .cfi_undefined 1
    );
    asm volatile (
        \\ move    $fp, $zero
        \\ move    $ra, $zero
        \\
        \\ ld.w    $t8, $sp, 0     # function pointer
        \\ ld.w    $a0, $sp, 4     # argument pointer
        \\ jirl    $ra, $t8, 0     # call the user's function
        \\ ori     $a7, $zero, 93  # SYS_exit
        \\ syscall 0               # child process exit
    );
}

pub const time_t = i64;

pub const VDSO = struct {
    pub const CGT_SYM = "__vdso_clock_gettime";
    pub const CGT_VER = "LINUX_5.10";
};
