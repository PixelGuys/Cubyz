const std = @import("std");
const builtin = @import("builtin");
const windows = std.os.windows;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    if (args.len < 2) return error.MissingArgs;

    const verify_path_wtf8 = args[1];
    const verify_path_w = try std.unicode.wtf8ToWtf16LeAllocZ(gpa, verify_path_wtf8);
    defer gpa.free(verify_path_w);

    const iterations: u64 = iterations: {
        if (args.len < 3) break :iterations 0;
        break :iterations try std.fmt.parseUnsigned(u64, args[2], 10);
    };

    var rand_seed = false;
    const seed: u64 = seed: {
        if (args.len < 4) {
            rand_seed = true;
            var buf: [8]u8 = undefined;
            io.random(&buf);
            break :seed std.mem.readInt(u64, &buf, builtin.cpu.arch.endian());
        }
        break :seed try std.fmt.parseUnsigned(u64, args[3], 10);
    };
    var random = std.Random.DefaultPrng.init(seed);
    const rand = random.random();

    // If the seed was not given via the CLI, then output the
    // randomly chosen seed so that this run can be reproduced
    if (rand_seed) {
        std.debug.print("rand seed: {}\n", .{seed});
    }

    var cmd_line_w_buf = std.array_list.Managed(u16).init(gpa);
    defer cmd_line_w_buf.deinit();

    var i: u64 = 0;
    var errors: u64 = 0;
    while (iterations == 0 or i < iterations) {
        const cmd_line_w = try randomCommandLineW(gpa, rand);
        defer gpa.free(cmd_line_w);

        // avoid known difference for 0-length command lines
        if (cmd_line_w.len == 0 or cmd_line_w[0] == '\x00') continue;

        const exit_code = try spawnVerify(verify_path_w, cmd_line_w);
        if (exit_code != 0) {
            std.debug.print(">>> found discrepancy <<<\n", .{});
            const cmd_line_wtf8 = try std.unicode.wtf16LeToWtf8Alloc(gpa, cmd_line_w);
            defer gpa.free(cmd_line_wtf8);
            std.debug.print("\"{f}\"\n\n", .{std.zig.fmtString(cmd_line_wtf8)});

            errors += 1;
        }

        i += 1;
    }
    if (errors > 0) {
        // we never get here if iterations is 0 so we don't have to worry about that case
        std.debug.print("found {} discrepancies in {} iterations\n", .{ errors, iterations });
        return error.FoundDiscrepancies;
    }
}

fn randomCommandLineW(allocator: Allocator, rand: std.Random) ![:0]const u16 {
    const Choice = enum {
        backslash,
        quote,
        space,
        tab,
        control,
        printable,
        non_ascii,
    };

    const choices = rand.uintAtMostBiased(u16, 256);
    var buf = try std.array_list.Managed(u16).initCapacity(allocator, choices);
    errdefer buf.deinit();

    for (0..choices) |_| {
        const choice = rand.enumValue(Choice);
        const code_unit = switch (choice) {
            .backslash => '\\',
            .quote => '"',
            .space => ' ',
            .tab => '\t',
            .control => switch (rand.uintAtMostBiased(u8, 0x21)) {
                0x21 => '\x7F',
                else => |b| b,
            },
            .printable => '!' + rand.uintAtMostBiased(u8, '~' - '!'),
            .non_ascii => rand.intRangeAtMostBiased(u16, 0x80, 0xFFFF),
        };
        try buf.append(std.mem.nativeToLittle(u16, code_unit));
    }

    return buf.toOwnedSliceSentinel(0);
}

/// Returns the exit code of the verify process
fn spawnVerify(verify_path: [:0]const u16, cmd_line: [:0]const u16) !windows.DWORD {
    const child_proc = spawn: {
        var startup_info: windows.STARTUPINFOW = .{
            .cb = @sizeOf(windows.STARTUPINFOW),
            .lpReserved = null,
            .lpDesktop = null,
            .lpTitle = null,
            .dwX = 0,
            .dwY = 0,
            .dwXSize = 0,
            .dwYSize = 0,
            .dwXCountChars = 0,
            .dwYCountChars = 0,
            .dwFillAttribute = 0,
            .dwFlags = windows.STARTF_USESTDHANDLES,
            .wShowWindow = 0,
            .cbReserved2 = 0,
            .lpReserved2 = null,
            .hStdInput = null,
            .hStdOutput = null,
            .hStdError = windows.peb().ProcessParameters.hStdError,
        };
        var proc_info: windows.PROCESS.INFORMATION = undefined;

        if (!windows.kernel32.CreateProcessW(
            @constCast(verify_path.ptr),
            @constCast(cmd_line.ptr),
            null,
            null,
            .TRUE,
            .{},
            null,
            null,
            &startup_info,
            &proc_info,
        ).toBool()) std.process.fatal("kernel32 CreateProcessW failed with {t}", .{windows.GetLastError()});

        windows.CloseHandle(proc_info.hThread);

        break :spawn proc_info.hProcess;
    };
    defer windows.CloseHandle(child_proc);
    const infinite_timeout: windows.LARGE_INTEGER = std.math.minInt(windows.LARGE_INTEGER);
    switch (windows.ntdll.NtWaitForSingleObject(child_proc, .FALSE, &infinite_timeout)) {
        windows.NTSTATUS.WAIT_0 => {},
        .TIMEOUT => return error.WaitTimeOut,
        else => |status| return windows.unexpectedStatus(status),
    }

    var info: windows.PROCESS.BASIC_INFORMATION = undefined;
    switch (windows.ntdll.NtQueryInformationProcess(
        child_proc,
        .BasicInformation,
        &info,
        @sizeOf(windows.PROCESS.BASIC_INFORMATION),
        null,
    )) {
        .SUCCESS => return @intFromEnum(info.ExitStatus),
        else => return error.UnableToGetExitCode,
    }
}
