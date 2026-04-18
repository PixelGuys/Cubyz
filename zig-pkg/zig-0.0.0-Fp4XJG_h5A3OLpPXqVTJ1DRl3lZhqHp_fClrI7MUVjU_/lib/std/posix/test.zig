const builtin = @import("builtin");
const native_os = builtin.target.os.tag;
const AtomicRmwOp = std.builtin.AtomicRmwOp;
const AtomicOrder = std.builtin.AtomicOrder;

const std = @import("../std.zig");
const Io = std.Io;
const Dir = std.Io.Dir;
const posix = std.posix;
const mem = std.mem;
const elf = std.elf;
const linux = std.os.linux;
const AT = std.posix.AT;

const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const expectEqualStrings = std.testing.expectEqualStrings;
const expectError = std.testing.expectError;
const tmpDir = std.testing.tmpDir;

const fstest = @import("../fs/test.zig");

test "check WASI CWD" {
    if (native_os == .wasi) {
        const cwd: Dir = .cwd();
        if (cwd.handle != 3) {
            @panic("WASI code that uses cwd (like this test) needs a preopen for cwd (add '--dir=.' to wasmtime)");
        }
        if (!builtin.link_libc) {
            // WASI without-libc hardcodes fd 3 as the FDCWD token so it can be passed directly to WASI calls
            try expectEqual(3, posix.AT.FDCWD);
        }
    }
}

test "getuid" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest;
    _ = posix.system.getuid();
    _ = posix.system.geteuid();
}

test "getgid" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest;
    _ = posix.system.getgid();
    _ = posix.system.getegid();
}

test "sigaltstack" {
    if (native_os == .windows or native_os == .wasi) return error.SkipZigTest;

    var st: posix.stack_t = undefined;
    try posix.sigaltstack(null, &st);
    // Setting a stack size less than MINSIGSTKSZ returns ENOMEM
    st.flags = 0;
    st.size = 1;
    try expectError(error.SizeTooSmall, posix.sigaltstack(&st, null));
}

// If the type is not available use void to avoid erroring out when `iter_fn` is
// analyzed
const have_dl_phdr_info = posix.system.dl_phdr_info != void;
const dl_phdr_info = if (have_dl_phdr_info) posix.dl_phdr_info else anyopaque;

const IterFnError = error{
    MissingPtLoadSegment,
    MissingLoad,
    BadElfMagic,
    FailedConsistencyCheck,
};

fn iter_fn(info: *dl_phdr_info, size: usize, counter: *usize) IterFnError!void {
    _ = size;
    // Count how many libraries are loaded
    counter.* += @as(usize, 1);

    // The image should contain at least a PT_LOAD segment
    if (info.phnum < 1) return error.MissingPtLoadSegment;

    // Quick & dirty validation of the phdr pointers, make sure we're not
    // pointing to some random gibberish
    var i: usize = 0;
    var found_load = false;
    while (i < info.phnum) : (i += 1) {
        const phdr = info.phdr[i];

        if (phdr.type != .LOAD) continue;

        const reloc_addr = info.addr + phdr.vaddr;
        // Find the ELF header
        const elf_header = @as(*elf.Ehdr, @ptrFromInt(reloc_addr - phdr.offset));
        // Validate the magic
        if (!mem.eql(u8, elf_header.e_ident[0..4], elf.MAGIC)) return error.BadElfMagic;
        // Consistency check
        if (elf_header.e_phnum != info.phnum) return error.FailedConsistencyCheck;

        found_load = true;
        break;
    }

    if (!found_load) return error.MissingLoad;
}

test "dl_iterate_phdr" {
    if (builtin.object_format != .elf) return error.SkipZigTest;

    var counter: usize = 0;
    try posix.dl_iterate_phdr(&counter, IterFnError, iter_fn);
    try expect(counter != 0);
}

test "gethostname" {
    if (native_os == .windows or native_os == .wasi)
        return error.SkipZigTest;

    var buf: [posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = try posix.gethostname(&buf);
    try expect(hostname.len != 0);
}

test "pipe" {
    if (native_os == .windows or native_os == .wasi)
        return error.SkipZigTest;

    const io = testing.io;

    const fds = try std.Io.Threaded.pipe2(.{});
    const out: Io.File = .{ .handle = fds[0], .flags = .{ .nonblocking = false } };
    const in: Io.File = .{ .handle = fds[1], .flags = .{ .nonblocking = false } };
    try in.writeStreamingAll(io, "hello");
    var buf: [16]u8 = undefined;
    try expect((try out.readStreaming(io, &.{&buf})) == 5);

    try expectEqualSlices(u8, buf[0..5], "hello");
    out.close(io);
    in.close(io);
}

test "memfd_create" {
    const io = testing.io;

    // memfd_create is only supported by linux and freebsd.
    switch (native_os) {
        .linux => {},
        .freebsd => {
            if (comptime builtin.os.version_range.semver.max.order(.{ .major = 13, .minor = 0, .patch = 0 }) == .lt)
                return error.SkipZigTest;
        },
        else => return error.SkipZigTest,
    }

    const file: Io.File = .{
        .handle = try posix.memfd_create("test", 0),
        .flags = .{ .nonblocking = false },
    };
    defer file.close(io);
    try file.writePositionalAll(io, "test", 0);

    var buf: [10]u8 = undefined;
    const bytes_read = try file.readPositionalAll(io, &buf, 0);
    try expect(bytes_read == 4);
    try expectEqualStrings("test", buf[0..4]);
}

test "mmap" {
    if (native_os == .windows or native_os == .wasi)
        return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    // Simple mmap() call with non page-aligned size
    {
        const data = try posix.mmap(
            null,
            1234,
            .{ .READ = true, .WRITE = true },
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
            -1,
            0,
        );
        defer posix.munmap(data);

        try expectEqual(@as(usize, 1234), data.len);

        // By definition the data returned by mmap is zero-filled
        try expect(mem.eql(u8, data, &[_]u8{0x00} ** 1234));

        // Make sure the memory is writeable as requested
        @memset(data, 0x55);
        try expect(mem.eql(u8, data, &[_]u8{0x55} ** 1234));
    }

    const test_out_file = "os_tmp_test";
    // Must be a multiple of the page size so that the test works with mmap2
    const alloc_size = 8 * std.heap.pageSize();

    // Create a file used for testing mmap() calls with a file descriptor
    {
        const file = try tmp.dir.createFile(io, test_out_file, .{});
        defer file.close(io);

        var stream = file.writer(io, &.{});

        var i: usize = 0;
        while (i < alloc_size / @sizeOf(u32)) : (i += 1) {
            try stream.interface.writeInt(u32, @intCast(i), .little);
        }
    }

    // Map the whole file
    {
        const file = try tmp.dir.openFile(io, test_out_file, .{});
        defer file.close(io);

        const data = try posix.mmap(
            null,
            alloc_size,
            .{ .READ = true },
            .{ .TYPE = .PRIVATE },
            file.handle,
            0,
        );
        defer posix.munmap(data);

        var stream: std.Io.Reader = .fixed(data);

        var i: usize = 0;
        while (i < alloc_size / @sizeOf(u32)) : (i += 1) {
            try expectEqual(i, try stream.takeInt(u32, .little));
        }
    }

    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest;

    // Map the upper half of the file
    {
        const file = try tmp.dir.openFile(io, test_out_file, .{});
        defer file.close(io);

        const data = try posix.mmap(
            null,
            alloc_size / 2,
            .{ .READ = true },
            .{ .TYPE = .PRIVATE },
            file.handle,
            alloc_size / 2,
        );
        defer posix.munmap(data);

        var stream: std.Io.Reader = .fixed(data);

        var i: usize = alloc_size / 2 / @sizeOf(u32);
        while (i < alloc_size / @sizeOf(u32)) : (i += 1) {
            try expectEqual(i, try stream.takeInt(u32, .little));
        }
    }
}

test "fcntl" {
    if (native_os == .windows or native_os == .wasi)
        return error.SkipZigTest;

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const test_out_file = "os_tmp_test";

    const file = try tmp.dir.createFile(io, test_out_file, .{});
    defer file.close(io);

    // Note: The test assumes createFile opens the file with CLOEXEC
    {
        const flags = posix.system.fcntl(file.handle, posix.F.GETFD, @as(usize, 0));
        try expect((flags & posix.FD_CLOEXEC) != 0);
    }
    {
        _ = posix.system.fcntl(file.handle, posix.F.SETFD, @as(usize, 0));
        const flags = posix.system.fcntl(file.handle, posix.F.GETFD, @as(usize, 0));
        try expect((flags & posix.FD_CLOEXEC) == 0);
    }
    {
        _ = posix.system.fcntl(file.handle, posix.F.SETFD, @as(usize, posix.FD_CLOEXEC));
        const flags = posix.system.fcntl(file.handle, posix.F.GETFD, @as(usize, 0));
        try expect((flags & posix.FD_CLOEXEC) != 0);
    }
}

test "signalfd" {
    switch (native_os) {
        .linux, .illumos => {},
        else => return error.SkipZigTest,
    }
    _ = &posix.signalfd;
}

test "sync" {
    if (native_os != .linux)
        return error.SkipZigTest;

    // Unfortunately, we cannot safely call `sync` or `syncfs`, because if file IO is happening
    // than the system can commit the results to disk, such calls could block indefinitely.

    _ = &posix.sync;
    _ = &posix.syncfs;
}

test "fsync" {
    switch (native_os) {
        .linux, .illumos => {},
        else => return error.SkipZigTest,
    }

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const test_out_file = "os_tmp_test";
    const file = try tmp.dir.createFile(io, test_out_file, .{});
    defer file.close(io);

    try file.sync(io);
    try posix.fdatasync(file.handle);
}

test "getrlimit and setrlimit" {
    if (posix.system.rlimit_resource == void) return error.SkipZigTest;

    inline for (@typeInfo(posix.rlimit_resource).@"enum".fields) |field| {
        const resource: posix.rlimit_resource = @enumFromInt(field.value);
        const limit = try posix.getrlimit(resource);

        // XNU kernel does not support RLIMIT_STACK if a custom stack is active,
        // which looks to always be the case. EINVAL is returned.
        // See https://github.com/apple-oss-distributions/xnu/blob/5e3eaea39dcf651e66cb99ba7d70e32cc4a99587/bsd/kern/kern_resource.c#L1173
        if (native_os.isDarwin() and resource == .STACK) {
            continue;
        }

        // On 32 bit MIPS musl includes a fix which changes limits greater than -1UL/2 to RLIM_INFINITY.
        // See http://git.musl-libc.org/cgit/musl/commit/src/misc/getrlimit.c?id=8258014fd1e34e942a549c88c7e022a00445c352
        //
        // This happens for example if RLIMIT_MEMLOCK is bigger than ~2GiB.
        // In that case the following the limit would be RLIM_INFINITY and the following setrlimit fails with EPERM.
        if (builtin.cpu.arch.isMIPS() and builtin.link_libc) {
            if (limit.cur != linux.RLIM.INFINITY) {
                try posix.setrlimit(resource, limit);
            }
        } else {
            try posix.setrlimit(resource, limit);
        }
    }
}

test "sigrtmin/max" {
    if (native_os.isDarwin() or switch (native_os) {
        .wasi, .windows, .openbsd, .dragonfly => true,
        else => false,
    }) return error.SkipZigTest;

    try expect(posix.sigrtmin() >= 32);
    try expect(posix.sigrtmin() >= posix.system.sigrtmin());
    try expect(posix.sigrtmin() < posix.system.sigrtmax());
}

test "sigset empty/full" {
    if (native_os == .wasi or native_os == .windows)
        return error.SkipZigTest;

    var set: posix.sigset_t = posix.sigemptyset();
    for (1..posix.NSIG) |i| {
        const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
        try expectEqual(false, posix.sigismember(&set, sig));
    }

    // The C library can reserve some (unnamed) signals, so can't check the full
    // NSIG set is defined, but just test a couple:
    set = posix.sigfillset();
    try expectEqual(true, posix.sigismember(&set, .CHLD));
    try expectEqual(true, posix.sigismember(&set, .INT));
}

// Some signals (i.e., 32 - 34 on glibc/musl) are not allowed to be added to a
// sigset by the C library, so avoid testing them.
fn reserved_signo(i: usize) bool {
    if (native_os.isDarwin()) return false;
    if (!builtin.link_libc) return false;
    const max = if (native_os == .netbsd) 32 else 31;
    if (i > max) return true;
    if (native_os == .openbsd or native_os == .dragonfly) return false; // no RT signals
    return i < posix.sigrtmin();
}

test "sigset add/del" {
    if (native_os == .wasi or native_os == .windows)
        return error.SkipZigTest;

    var sigset: posix.sigset_t = posix.sigemptyset();

    // See that none are set, then set each one, see that they're all set, then
    // remove them all, and then see that none are set.
    for (1..posix.NSIG) |i| {
        const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
        try expectEqual(false, posix.sigismember(&sigset, sig));
    }
    for (1..posix.NSIG) |i| {
        if (!reserved_signo(i)) {
            const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
            posix.sigaddset(&sigset, sig);
        }
    }
    for (1..posix.NSIG) |i| {
        if (!reserved_signo(i)) {
            const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
            try expectEqual(true, posix.sigismember(&sigset, sig));
        }
    }
    for (1..posix.NSIG) |i| {
        if (!reserved_signo(i)) {
            const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
            posix.sigdelset(&sigset, sig);
        }
    }
    for (1..posix.NSIG) |i| {
        const sig = std.enums.fromInt(posix.SIG, i) orelse continue;
        try expectEqual(false, posix.sigismember(&sigset, sig));
    }
}

test "getpid" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;

    try expect(posix.system.getpid() != 0);
}

test "getppid" {
    if (native_os == .wasi) return error.SkipZigTest;
    if (native_os == .windows) return error.SkipZigTest;
    if (native_os == .plan9 and !builtin.link_libc) return error.SkipZigTest;

    try expect(posix.getppid() >= 0);
}

test "rename smoke test" {
    if (native_os == .windows) return error.SkipZigTest;
    if (!fstest.isRealPathSupported()) return error.SkipZigTest;

    const io = testing.io;
    const gpa = testing.allocator;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const base_path = try tmp.dir.realPathFileAlloc(io, ".", gpa);
    defer gpa.free(base_path);

    const mode: posix.mode_t = if (native_os == .windows) 0 else 0o666;

    {
        // Create some file using `open`.
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_file" });
        defer gpa.free(file_path);
        const file = try Io.Dir.cwd().createFile(io, file_path, .{
            .read = true,
            .exclusive = true,
            .permissions = .fromMode(mode),
        });
        file.close(io);

        // Rename the file
        const new_file_path = try Dir.path.join(gpa, &.{ base_path, "some_other_file" });
        defer gpa.free(new_file_path);
        try Io.Dir.renameAbsolute(file_path, new_file_path, io);
    }

    {
        // Try opening renamed file
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_other_file" });
        defer gpa.free(file_path);
        const file = try Io.Dir.cwd().openFile(io, file_path, .{ .mode = .read_write });
        file.close(io);
    }

    {
        // Try opening original file - should fail with error.FileNotFound
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_file" });
        defer gpa.free(file_path);
        try expectError(error.FileNotFound, Io.Dir.cwd().openFile(io, file_path, .{ .mode = .read_write }));
    }

    {
        // Create some directory
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_dir" });
        defer gpa.free(file_path);
        try Io.Dir.createDirAbsolute(io, file_path, .fromMode(mode));

        // Rename the directory
        const new_file_path = try Dir.path.join(gpa, &.{ base_path, "some_other_dir" });
        defer gpa.free(new_file_path);
        try Io.Dir.renameAbsolute(file_path, new_file_path, io);
    }

    {
        // Try opening renamed directory
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_other_dir" });
        defer gpa.free(file_path);
        const dir = try Io.Dir.cwd().openDir(io, file_path, .{});
        dir.close(io);
    }

    {
        // Try opening original directory - should fail with error.FileNotFound
        const file_path = try Dir.path.join(gpa, &.{ base_path, "some_dir" });
        defer gpa.free(file_path);
        try expectError(error.FileNotFound, Io.Dir.cwd().openDir(io, file_path, .{}));
    }
}
