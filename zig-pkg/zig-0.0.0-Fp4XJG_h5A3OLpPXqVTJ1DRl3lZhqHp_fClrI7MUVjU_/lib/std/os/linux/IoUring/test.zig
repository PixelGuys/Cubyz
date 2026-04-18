const builtin = @import("builtin");

const std = @import("../../../std.zig");
const Io = std.Io;
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;
const linux = std.os.linux;

const IoUring = std.os.linux.IoUring;
const BufferGroup = IoUring.BufferGroup;

const posix = std.posix;
const iovec = posix.iovec;
const iovec_const = posix.iovec_const;

comptime {
    assert(builtin.os.tag == .linux);
}

test "structs/offsets/entries" {
    try testing.expectEqual(@as(usize, 120), @sizeOf(linux.io_uring_params));
    try testing.expectEqual(@as(usize, 64), @sizeOf(linux.io_uring_sqe));
    try testing.expectEqual(@as(usize, 16), @sizeOf(linux.io_uring_cqe));

    try testing.expectEqual(0, linux.IORING_OFF_SQ_RING);
    try testing.expectEqual(0x8000000, linux.IORING_OFF_CQ_RING);
    try testing.expectEqual(0x10000000, linux.IORING_OFF_SQES);

    try testing.expectError(error.EntriesZero, IoUring.init(0, 0));
    try testing.expectError(error.EntriesNotPowerOfTwo, IoUring.init(3, 0));
}

test "nop" {
    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer {
        ring.deinit();
        testing.expectEqual(@as(linux.fd_t, -1), ring.fd) catch @panic("test failed");
    }

    const sqe = try ring.nop(0xaaaaaaaa);
    try testing.expectEqual(linux.io_uring_sqe{
        .opcode = .NOP,
        .flags = 0,
        .ioprio = 0,
        .fd = 0,
        .off = 0,
        .addr = 0,
        .len = 0,
        .rw_flags = 0,
        .user_data = 0xaaaaaaaa,
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    }, sqe.*);

    try testing.expectEqual(@as(u32, 0), ring.sq.sqe_head);
    try testing.expectEqual(@as(u32, 1), ring.sq.sqe_tail);
    try testing.expectEqual(@as(u32, 0), ring.sq.tail.*);
    try testing.expectEqual(@as(u32, 0), ring.cq.head.*);
    try testing.expectEqual(@as(u32, 1), ring.sq_ready());
    try testing.expectEqual(@as(u32, 0), ring.cq_ready());

    try testing.expectEqual(@as(u32, 1), try ring.submit());
    try testing.expectEqual(@as(u32, 1), ring.sq.sqe_head);
    try testing.expectEqual(@as(u32, 1), ring.sq.sqe_tail);
    try testing.expectEqual(@as(u32, 1), ring.sq.tail.*);
    try testing.expectEqual(@as(u32, 0), ring.cq.head.*);
    try testing.expectEqual(@as(u32, 0), ring.sq_ready());

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xaaaaaaaa,
        .res = 0,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqual(@as(u32, 1), ring.cq.head.*);
    try testing.expectEqual(@as(u32, 0), ring.cq_ready());

    const sqe_barrier = try ring.nop(0xbbbbbbbb);
    sqe_barrier.flags |= linux.IOSQE_IO_DRAIN;
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xbbbbbbbb,
        .res = 0,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqual(@as(u32, 2), ring.sq.sqe_head);
    try testing.expectEqual(@as(u32, 2), ring.sq.sqe_tail);
    try testing.expectEqual(@as(u32, 2), ring.sq.tail.*);
    try testing.expectEqual(@as(u32, 2), ring.cq.head.*);
}

test "readv" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const file = try Io.Dir.openFileAbsolute(io, "/dev/zero", .{});
    defer file.close(io);

    // Linux Kernel 5.4 supports IORING_REGISTER_FILES but not sparse fd sets (i.e. an fd of -1).
    // Linux Kernel 5.5 adds support for sparse fd sets.
    // Compare:
    // https://github.com/torvalds/linux/blob/v5.4/fs/io_uring.c#L3119-L3124 vs
    // https://github.com/torvalds/linux/blob/v5.8/fs/io_uring.c#L6687-L6691
    // We therefore avoid stressing sparse fd sets here:
    var registered_fds = [_]linux.fd_t{0} ** 1;
    const fd_index = 0;
    registered_fds[fd_index] = file.handle;
    try ring.register_files(registered_fds[0..]);

    var buffer = [_]u8{42} ** 128;
    var iovecs = [_]iovec{iovec{ .base = &buffer, .len = buffer.len }};
    const sqe = try ring.read(0xcccccccc, fd_index, .{ .iovecs = iovecs[0..] }, 0);
    try testing.expectEqual(linux.IORING_OP.READV, sqe.opcode);
    sqe.flags |= linux.IOSQE_FIXED_FILE;

    try testing.expectError(error.SubmissionQueueFull, ring.nop(0));
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xcccccccc,
        .res = buffer.len,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer.len), buffer[0..]);

    try ring.unregister_files();
}

test "writev/fsync/readv" {
    const io = testing.io;

    var ring = IoUring.init(4, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_writev_fsync_readv";
    const file = try tmp.dir.createFile(io, path, .{ .read = true });
    defer file.close(io);
    const fd = file.handle;

    const buffer_write = [_]u8{42} ** 128;
    const iovecs_write = [_]iovec_const{
        iovec_const{ .base = &buffer_write, .len = buffer_write.len },
    };
    var buffer_read = [_]u8{0} ** 128;
    var iovecs_read = [_]iovec{
        iovec{ .base = &buffer_read, .len = buffer_read.len },
    };

    const sqe_writev = try ring.writev(0xdddddddd, fd, iovecs_write[0..], 17);
    try testing.expectEqual(linux.IORING_OP.WRITEV, sqe_writev.opcode);
    try testing.expectEqual(@as(u64, 17), sqe_writev.off);
    sqe_writev.flags |= linux.IOSQE_IO_LINK;

    const sqe_fsync = try ring.fsync(0xeeeeeeee, fd, 0);
    try testing.expectEqual(linux.IORING_OP.FSYNC, sqe_fsync.opcode);
    try testing.expectEqual(fd, sqe_fsync.fd);
    sqe_fsync.flags |= linux.IOSQE_IO_LINK;

    const sqe_readv = try ring.read(0xffffffff, fd, .{ .iovecs = iovecs_read[0..] }, 17);
    try testing.expectEqual(linux.IORING_OP.READV, sqe_readv.opcode);
    try testing.expectEqual(@as(u64, 17), sqe_readv.off);

    try testing.expectEqual(@as(u32, 3), ring.sq_ready());
    try testing.expectEqual(@as(u32, 3), try ring.submit_and_wait(3));
    try testing.expectEqual(@as(u32, 0), ring.sq_ready());
    try testing.expectEqual(@as(u32, 3), ring.cq_ready());

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xdddddddd,
        .res = buffer_write.len,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqual(@as(u32, 2), ring.cq_ready());

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xeeeeeeee,
        .res = 0,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqual(@as(u32, 1), ring.cq_ready());

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xffffffff,
        .res = buffer_read.len,
        .flags = 0,
    }, try ring.copy_cqe());
    try testing.expectEqual(@as(u32, 0), ring.cq_ready());

    try testing.expectEqualSlices(u8, buffer_write[0..], buffer_read[0..]);
}

test "write/read" {
    const io = testing.io;

    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = "test_io_uring_write_read";
    const file = try tmp.dir.createFile(io, path, .{ .read = true });
    defer file.close(io);
    const fd = file.handle;

    const buffer_write = [_]u8{97} ** 20;
    var buffer_read = [_]u8{98} ** 20;
    const sqe_write = try ring.write(0x11111111, fd, buffer_write[0..], 10);
    try testing.expectEqual(linux.IORING_OP.WRITE, sqe_write.opcode);
    try testing.expectEqual(@as(u64, 10), sqe_write.off);
    sqe_write.flags |= linux.IOSQE_IO_LINK;
    const sqe_read = try ring.read(0x22222222, fd, .{ .buffer = buffer_read[0..] }, 10);
    try testing.expectEqual(linux.IORING_OP.READ, sqe_read.opcode);
    try testing.expectEqual(@as(u64, 10), sqe_read.off);
    try testing.expectEqual(@as(u32, 2), try ring.submit());

    const cqe_write = try ring.copy_cqe();
    const cqe_read = try ring.copy_cqe();
    // Prior to Linux Kernel 5.6 this is the only way to test for read/write support:
    // https://lwn.net/Articles/809820/
    if (cqe_write.err() == .INVAL) return error.SkipZigTest;
    if (cqe_read.err() == .INVAL) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x11111111,
        .res = buffer_write.len,
        .flags = 0,
    }, cqe_write);
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x22222222,
        .res = buffer_read.len,
        .flags = 0,
    }, cqe_read);
    try testing.expectEqualSlices(u8, buffer_write[0..], buffer_read[0..]);
}

test "splice/read" {
    const io = testing.io;

    var ring = IoUring.init(4, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    const path_src = "test_io_uring_splice_src";
    const file_src = try tmp.dir.createFile(io, path_src, .{ .read = true });
    defer file_src.close(io);
    const fd_src = file_src.handle;

    const path_dst = "test_io_uring_splice_dst";
    const file_dst = try tmp.dir.createFile(io, path_dst, .{ .read = true });
    defer file_dst.close(io);
    const fd_dst = file_dst.handle;

    const buffer_write = [_]u8{97} ** 20;
    var buffer_read = [_]u8{98} ** 20;
    try file_src.writeStreamingAll(io, &buffer_write);

    const fds = try std.Io.Threaded.pipe2(.{});
    const pipe_offset: u64 = std.math.maxInt(u64);

    const sqe_splice_to_pipe = try ring.splice(0x11111111, fd_src, 0, fds[1], pipe_offset, buffer_write.len);
    try testing.expectEqual(linux.IORING_OP.SPLICE, sqe_splice_to_pipe.opcode);
    try testing.expectEqual(@as(u64, 0), sqe_splice_to_pipe.addr);
    try testing.expectEqual(pipe_offset, sqe_splice_to_pipe.off);
    sqe_splice_to_pipe.flags |= linux.IOSQE_IO_LINK;

    const sqe_splice_from_pipe = try ring.splice(0x22222222, fds[0], pipe_offset, fd_dst, 10, buffer_write.len);
    try testing.expectEqual(linux.IORING_OP.SPLICE, sqe_splice_from_pipe.opcode);
    try testing.expectEqual(pipe_offset, sqe_splice_from_pipe.addr);
    try testing.expectEqual(@as(u64, 10), sqe_splice_from_pipe.off);
    sqe_splice_from_pipe.flags |= linux.IOSQE_IO_LINK;

    const sqe_read = try ring.read(0x33333333, fd_dst, .{ .buffer = buffer_read[0..] }, 10);
    try testing.expectEqual(linux.IORING_OP.READ, sqe_read.opcode);
    try testing.expectEqual(@as(u64, 10), sqe_read.off);
    try testing.expectEqual(@as(u32, 3), try ring.submit());

    const cqe_splice_to_pipe = try ring.copy_cqe();
    const cqe_splice_from_pipe = try ring.copy_cqe();
    const cqe_read = try ring.copy_cqe();
    // Prior to Linux Kernel 5.6 this is the only way to test for splice/read support:
    // https://lwn.net/Articles/809820/
    if (cqe_splice_to_pipe.err() == .INVAL) return error.SkipZigTest;
    if (cqe_splice_from_pipe.err() == .INVAL) return error.SkipZigTest;
    if (cqe_read.err() == .INVAL) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x11111111,
        .res = buffer_write.len,
        .flags = 0,
    }, cqe_splice_to_pipe);
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x22222222,
        .res = buffer_write.len,
        .flags = 0,
    }, cqe_splice_from_pipe);
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x33333333,
        .res = buffer_read.len,
        .flags = 0,
    }, cqe_read);
    try testing.expectEqualSlices(u8, buffer_write[0..], buffer_read[0..]);
}

test "write_fixed/read_fixed" {
    const io = testing.io;

    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_write_read_fixed";
    const file = try tmp.dir.createFile(io, path, .{ .read = true });
    defer file.close(io);
    const fd = file.handle;

    var raw_buffers: [2][11]u8 = undefined;
    // First buffer will be written to the file.
    @memset(&raw_buffers[0], 'z');
    raw_buffers[0][0.."foobar".len].* = "foobar".*;

    var buffers = [2]iovec{
        .{ .base = &raw_buffers[0], .len = raw_buffers[0].len },
        .{ .base = &raw_buffers[1], .len = raw_buffers[1].len },
    };
    ring.register_buffers(&buffers) catch |err| switch (err) {
        error.SystemResources => {
            // See https://github.com/ziglang/zig/issues/15362
            return error.SkipZigTest;
        },
        else => |e| return e,
    };

    const sqe_write = try ring.write_fixed(0x45454545, fd, &buffers[0], 3, 0);
    try testing.expectEqual(linux.IORING_OP.WRITE_FIXED, sqe_write.opcode);
    try testing.expectEqual(@as(u64, 3), sqe_write.off);
    sqe_write.flags |= linux.IOSQE_IO_LINK;

    const sqe_read = try ring.read_fixed(0x12121212, fd, &buffers[1], 0, 1);
    try testing.expectEqual(linux.IORING_OP.READ_FIXED, sqe_read.opcode);
    try testing.expectEqual(@as(u64, 0), sqe_read.off);

    try testing.expectEqual(@as(u32, 2), try ring.submit());

    const cqe_write = try ring.copy_cqe();
    const cqe_read = try ring.copy_cqe();

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x45454545,
        .res = @as(i32, @intCast(buffers[0].len)),
        .flags = 0,
    }, cqe_write);
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = @as(i32, @intCast(buffers[1].len)),
        .flags = 0,
    }, cqe_read);

    try testing.expectEqualSlices(u8, "\x00\x00\x00", buffers[1].base[0..3]);
    try testing.expectEqualSlices(u8, "foobar", buffers[1].base[3..9]);
    try testing.expectEqualSlices(u8, "zz", buffers[1].base[9..11]);
}

test "openat" {
    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_openat";

    // Workaround for LLVM bug: https://github.com/ziglang/zig/issues/12014
    const path_addr = if (builtin.zig_backend == .stage2_llvm) p: {
        var workaround = path;
        _ = &workaround;
        break :p @intFromPtr(workaround);
    } else @intFromPtr(path);

    const flags: linux.O = .{ .CLOEXEC = true, .ACCMODE = .RDWR, .CREAT = true };
    const mode: posix.mode_t = 0o666;
    const sqe_openat = try ring.openat(0x33333333, tmp.dir.handle, path, flags, mode);
    try testing.expectEqual(linux.io_uring_sqe{
        .opcode = .OPENAT,
        .flags = 0,
        .ioprio = 0,
        .fd = tmp.dir.handle,
        .off = 0,
        .addr = path_addr,
        .len = mode,
        .rw_flags = @bitCast(flags),
        .user_data = 0x33333333,
        .buf_index = 0,
        .personality = 0,
        .splice_fd_in = 0,
        .addr3 = 0,
        .resv = 0,
    }, sqe_openat.*);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe_openat = try ring.copy_cqe();
    try testing.expectEqual(@as(u64, 0x33333333), cqe_openat.user_data);
    if (cqe_openat.err() == .INVAL) return error.SkipZigTest;
    if (cqe_openat.err() == .BADF) return error.SkipZigTest;
    if (cqe_openat.res <= 0) std.debug.print("\ncqe_openat.res={}\n", .{cqe_openat.res});
    try testing.expect(cqe_openat.res > 0);
    try testing.expectEqual(@as(u32, 0), cqe_openat.flags);

    _ = linux.close(cqe_openat.res);
}

test "close" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_close";
    const file = try tmp.dir.createFile(io, path, .{});
    errdefer file.close(io);

    const sqe_close = try ring.close(0x44444444, file.handle);
    try testing.expectEqual(linux.IORING_OP.CLOSE, sqe_close.opcode);
    try testing.expectEqual(file.handle, sqe_close.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe_close = try ring.copy_cqe();
    if (cqe_close.err() == .INVAL) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x44444444,
        .res = 0,
        .flags = 0,
    }, cqe_close);
}

test "accept/connect/send/recv" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const socket_test_harness = try createSocketTestHarness(&ring);
    defer socket_test_harness.close();

    const buffer_send = [_]u8{ 1, 0, 1, 0, 1, 0, 1, 0, 1, 0 };
    var buffer_recv = [_]u8{ 0, 1, 0, 1, 0 };

    const sqe_send = try ring.send(0xeeeeeeee, socket_test_harness.client, buffer_send[0..], 0);
    sqe_send.flags |= linux.IOSQE_IO_LINK;
    _ = try ring.recv(0xffffffff, socket_test_harness.server, .{ .buffer = buffer_recv[0..] }, 0);
    try testing.expectEqual(@as(u32, 2), try ring.submit());

    const cqe_send = try ring.copy_cqe();
    if (cqe_send.err() == .INVAL) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xeeeeeeee,
        .res = buffer_send.len,
        .flags = 0,
    }, cqe_send);

    const cqe_recv = try ring.copy_cqe();
    if (cqe_recv.err() == .INVAL) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xffffffff,
        .res = buffer_recv.len,
        // ignore IORING_CQE_F_SOCK_NONEMPTY since it is only set on some systems
        .flags = cqe_recv.flags & linux.IORING_CQE_F_SOCK_NONEMPTY,
    }, cqe_recv);

    try testing.expectEqualSlices(u8, buffer_send[0..buffer_recv.len], buffer_recv[0..]);
}

test "sendmsg/recvmsg" {
    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var address_server: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };

    const server = try socket(address_server.family, posix.SOCK.DGRAM, 0);
    defer _ = linux.close(server);
    try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEPORT, &mem.toBytes(@as(c_int, 1)));
    try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEADDR, &mem.toBytes(@as(c_int, 1)));
    try bind(server, addrAny(&address_server), @sizeOf(linux.sockaddr.in));

    // set address_server to the OS-chosen IP/port.
    var slen: posix.socklen_t = @sizeOf(linux.sockaddr.in);
    try getsockname(server, addrAny(&address_server), &slen);

    const client = try socket(address_server.family, posix.SOCK.DGRAM, 0);
    defer _ = linux.close(client);

    const buffer_send = [_]u8{42} ** 128;
    const iovecs_send = [_]iovec_const{
        iovec_const{ .base = &buffer_send, .len = buffer_send.len },
    };
    const msg_send: linux.msghdr_const = .{
        .name = addrAny(&address_server),
        .namelen = @sizeOf(linux.sockaddr.in),
        .iov = &iovecs_send,
        .iovlen = 1,
        .control = null,
        .controllen = 0,
        .flags = 0,
    };
    const sqe_sendmsg = try ring.sendmsg(0x11111111, client, &msg_send, 0);
    sqe_sendmsg.flags |= linux.IOSQE_IO_LINK;
    try testing.expectEqual(linux.IORING_OP.SENDMSG, sqe_sendmsg.opcode);
    try testing.expectEqual(client, sqe_sendmsg.fd);

    var buffer_recv = [_]u8{0} ** 128;
    var iovecs_recv = [_]iovec{
        iovec{ .base = &buffer_recv, .len = buffer_recv.len },
    };
    var address_recv: linux.sockaddr.in = .{
        .port = 0,
        .addr = 0,
    };
    var msg_recv: linux.msghdr = .{
        .name = addrAny(&address_recv),
        .namelen = @sizeOf(linux.sockaddr.in),
        .iov = &iovecs_recv,
        .iovlen = 1,
        .control = null,
        .controllen = 0,
        .flags = 0,
    };
    const sqe_recvmsg = try ring.recvmsg(0x22222222, server, &msg_recv, 0);
    try testing.expectEqual(linux.IORING_OP.RECVMSG, sqe_recvmsg.opcode);
    try testing.expectEqual(server, sqe_recvmsg.fd);

    try testing.expectEqual(@as(u32, 2), ring.sq_ready());
    try testing.expectEqual(@as(u32, 2), try ring.submit_and_wait(2));
    try testing.expectEqual(@as(u32, 0), ring.sq_ready());
    try testing.expectEqual(@as(u32, 2), ring.cq_ready());

    const cqe_sendmsg = try ring.copy_cqe();
    if (cqe_sendmsg.res == -@as(i32, @intFromEnum(linux.E.INVAL))) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x11111111,
        .res = buffer_send.len,
        .flags = 0,
    }, cqe_sendmsg);

    const cqe_recvmsg = try ring.copy_cqe();
    if (cqe_recvmsg.res == -@as(i32, @intFromEnum(linux.E.INVAL))) return error.SkipZigTest;
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x22222222,
        .res = buffer_recv.len,
        // ignore IORING_CQE_F_SOCK_NONEMPTY since it is set non-deterministically
        .flags = cqe_recvmsg.flags & linux.IORING_CQE_F_SOCK_NONEMPTY,
    }, cqe_recvmsg);

    try testing.expectEqualSlices(u8, buffer_send[0..buffer_recv.len], buffer_recv[0..]);
}

test "timeout (after a relative time)" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const ms = 10;
    const margin = 5;
    const ts: linux.kernel_timespec = .{ .sec = 0, .nsec = ms * 1000000 };

    const started = std.Io.Clock.awake.now(io);
    const sqe = try ring.timeout(0x55555555, &ts, 0, 0);
    try testing.expectEqual(linux.IORING_OP.TIMEOUT, sqe.opcode);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    const cqe = try ring.copy_cqe();
    const stopped = std.Io.Clock.awake.now(io);

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x55555555,
        .res = -@as(i32, @intFromEnum(linux.E.TIME)),
        .flags = 0,
    }, cqe);

    // Tests should not depend on timings: skip test if outside margin.
    const ms_elapsed = started.durationTo(stopped).toMilliseconds();
    if (ms_elapsed > margin) return error.SkipZigTest;
}

test "timeout (after a number of completions)" {
    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const ts: linux.kernel_timespec = .{ .sec = 3, .nsec = 0 };
    const count_completions: u64 = 1;
    const sqe_timeout = try ring.timeout(0x66666666, &ts, count_completions, 0);
    try testing.expectEqual(linux.IORING_OP.TIMEOUT, sqe_timeout.opcode);
    try testing.expectEqual(count_completions, sqe_timeout.off);
    _ = try ring.nop(0x77777777);
    try testing.expectEqual(@as(u32, 2), try ring.submit());

    const cqe_nop = try ring.copy_cqe();
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x77777777,
        .res = 0,
        .flags = 0,
    }, cqe_nop);

    const cqe_timeout = try ring.copy_cqe();
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x66666666,
        .res = 0,
        .flags = 0,
    }, cqe_timeout);
}

test "timeout_remove" {
    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const ts: linux.kernel_timespec = .{ .sec = 3, .nsec = 0 };
    const sqe_timeout = try ring.timeout(0x88888888, &ts, 0, 0);
    try testing.expectEqual(linux.IORING_OP.TIMEOUT, sqe_timeout.opcode);
    try testing.expectEqual(@as(u64, 0x88888888), sqe_timeout.user_data);

    const sqe_timeout_remove = try ring.timeout_remove(0x99999999, 0x88888888, 0);
    try testing.expectEqual(linux.IORING_OP.TIMEOUT_REMOVE, sqe_timeout_remove.opcode);
    try testing.expectEqual(@as(u64, 0x88888888), sqe_timeout_remove.addr);
    try testing.expectEqual(@as(u64, 0x99999999), sqe_timeout_remove.user_data);

    try testing.expectEqual(@as(u32, 2), try ring.submit());

    // The order in which the CQE arrive is not clearly documented and it changed with kernel 5.18:
    // * kernel 5.10 gives user data 0x88888888 first, 0x99999999 second
    // * kernel 5.18 gives user data 0x99999999 first, 0x88888888 second

    var cqes: [2]linux.io_uring_cqe = undefined;
    cqes[0] = try ring.copy_cqe();
    cqes[1] = try ring.copy_cqe();

    for (cqes) |cqe| {
        // IORING_OP_TIMEOUT_REMOVE is not supported by this kernel version:
        // Timeout remove operations set the fd to -1, which results in EBADF before EINVAL.
        // We use IORING_FEAT_RW_CUR_POS as a safety check here to make sure we are at least pre-5.6.
        // We don't want to skip this test for newer kernels.
        if (cqe.user_data == 0x99999999 and
            cqe.err() == .BADF and
            (ring.features & linux.IORING_FEAT_RW_CUR_POS) == 0)
        {
            return error.SkipZigTest;
        }

        try testing.expect(cqe.user_data == 0x88888888 or cqe.user_data == 0x99999999);

        if (cqe.user_data == 0x88888888) {
            try testing.expectEqual(linux.io_uring_cqe{
                .user_data = 0x88888888,
                .res = -@as(i32, @intFromEnum(linux.E.CANCELED)),
                .flags = 0,
            }, cqe);
        } else if (cqe.user_data == 0x99999999) {
            try testing.expectEqual(linux.io_uring_cqe{
                .user_data = 0x99999999,
                .res = 0,
                .flags = 0,
            }, cqe);
        }
    }
}

test "accept/connect/recv/link_timeout" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const socket_test_harness = try createSocketTestHarness(&ring);
    defer socket_test_harness.close();

    var buffer_recv = [_]u8{ 0, 1, 0, 1, 0 };

    const sqe_recv = try ring.recv(0xffffffff, socket_test_harness.server, .{ .buffer = buffer_recv[0..] }, 0);
    sqe_recv.flags |= linux.IOSQE_IO_LINK;

    const ts = linux.kernel_timespec{ .sec = 0, .nsec = 1000000 };
    _ = try ring.link_timeout(0x22222222, &ts, 0);

    const nr_wait = try ring.submit();
    try testing.expectEqual(@as(u32, 2), nr_wait);

    var i: usize = 0;
    while (i < nr_wait) : (i += 1) {
        const cqe = try ring.copy_cqe();
        switch (cqe.user_data) {
            0xffffffff => {
                if (cqe.res != -@as(i32, @intFromEnum(linux.E.INTR)) and
                    cqe.res != -@as(i32, @intFromEnum(linux.E.CANCELED)))
                {
                    std.debug.print("Req 0x{x} got {d}\n", .{ cqe.user_data, cqe.res });
                    try testing.expect(false);
                }
            },
            0x22222222 => {
                if (cqe.res != -@as(i32, @intFromEnum(linux.E.ALREADY)) and
                    cqe.res != -@as(i32, @intFromEnum(linux.E.TIME)))
                {
                    std.debug.print("Req 0x{x} got {d}\n", .{ cqe.user_data, cqe.res });
                    try testing.expect(false);
                }
            },
            else => @panic("should not happen"),
        }
    }
}

test "fallocate" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_fallocate";
    const file = try tmp.dir.createFile(io, path, .{});
    defer file.close(io);

    try testing.expectEqual(@as(u64, 0), (try file.stat(io)).size);

    const len: u64 = 65536;
    const sqe = try ring.fallocate(0xaaaaaaaa, file.handle, 0, 0, len);
    try testing.expectEqual(linux.IORING_OP.FALLOCATE, sqe.opcode);
    try testing.expectEqual(file.handle, sqe.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement fallocate():
        .INVAL => return error.SkipZigTest,
        // This kernel does not implement fallocate():
        .NOSYS => return error.SkipZigTest,
        // The filesystem containing the file referred to by fd does not support this operation;
        // or the mode is not supported by the filesystem containing the file referred to by fd:
        .OPNOTSUPP => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xaaaaaaaa,
        .res = 0,
        .flags = 0,
    }, cqe);

    try testing.expectEqual(len, (try file.stat(io)).size);
}

test "statx" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = "test_io_uring_statx";
    const file = try tmp.dir.createFile(io, path, .{});
    defer file.close(io);

    try testing.expectEqual(@as(u64, 0), (try file.stat(io)).size);

    try file.writeStreamingAll(io, "foobar");

    var buf: linux.Statx = undefined;
    const sqe = try ring.statx(
        0xaaaaaaaa,
        tmp.dir.handle,
        path,
        0,
        .{ .SIZE = true },
        &buf,
    );
    try testing.expectEqual(linux.IORING_OP.STATX, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement statx():
        .INVAL => return error.SkipZigTest,
        // This kernel does not implement statx():
        .NOSYS => return error.SkipZigTest,
        // The filesystem containing the file referred to by fd does not support this operation;
        // or the mode is not supported by the filesystem containing the file referred to by fd:
        .OPNOTSUPP => return error.SkipZigTest,
        // not supported on older kernels (5.4)
        .BADF => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xaaaaaaaa,
        .res = 0,
        .flags = 0,
    }, cqe);

    try testing.expect(buf.mask.SIZE);
    try testing.expectEqual(@as(u64, 6), buf.size);
}

test "accept/connect/recv/cancel" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const socket_test_harness = try createSocketTestHarness(&ring);
    defer socket_test_harness.close();

    var buffer_recv = [_]u8{ 0, 1, 0, 1, 0 };

    _ = try ring.recv(0xffffffff, socket_test_harness.server, .{ .buffer = buffer_recv[0..] }, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const sqe_cancel = try ring.cancel(0x99999999, 0xffffffff, 0);
    try testing.expectEqual(linux.IORING_OP.ASYNC_CANCEL, sqe_cancel.opcode);
    try testing.expectEqual(@as(u64, 0xffffffff), sqe_cancel.addr);
    try testing.expectEqual(@as(u64, 0x99999999), sqe_cancel.user_data);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    var cqe_recv = try ring.copy_cqe();
    if (cqe_recv.err() == .INVAL) return error.SkipZigTest;
    var cqe_cancel = try ring.copy_cqe();
    if (cqe_cancel.err() == .INVAL) return error.SkipZigTest;

    // The recv/cancel CQEs may arrive in any order, the recv CQE will sometimes come first:
    if (cqe_recv.user_data == 0x99999999 and cqe_cancel.user_data == 0xffffffff) {
        const a = cqe_recv;
        const b = cqe_cancel;
        cqe_recv = b;
        cqe_cancel = a;
    }

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xffffffff,
        .res = -@as(i32, @intFromEnum(linux.E.CANCELED)),
        .flags = 0,
    }, cqe_recv);

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x99999999,
        .res = 0,
        .flags = 0,
    }, cqe_cancel);
}

test "register_files_update" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const file = try Io.Dir.openFileAbsolute(io, "/dev/zero", .{});
    defer file.close(io);

    var registered_fds = [_]linux.fd_t{0} ** 2;
    const fd_index = 0;
    const fd_index2 = 1;
    registered_fds[fd_index] = file.handle;
    registered_fds[fd_index2] = -1;

    ring.register_files(registered_fds[0..]) catch |err| switch (err) {
        // Happens when the kernel doesn't support sparse entry (-1) in the file descriptors array.
        error.FileDescriptorInvalid => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    };

    // Test IORING_REGISTER_FILES_UPDATE
    // Only available since Linux 5.5

    const file2 = try Io.Dir.openFileAbsolute(io, "/dev/zero", .{});
    defer file2.close(io);

    registered_fds[fd_index] = file2.handle;
    registered_fds[fd_index2] = -1;
    try ring.register_files_update(0, registered_fds[0..]);

    var buffer = [_]u8{42} ** 128;
    {
        const sqe = try ring.read(0xcccccccc, fd_index, .{ .buffer = &buffer }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        sqe.flags |= linux.IOSQE_FIXED_FILE;

        try testing.expectEqual(@as(u32, 1), try ring.submit());
        try testing.expectEqual(linux.io_uring_cqe{
            .user_data = 0xcccccccc,
            .res = buffer.len,
            .flags = 0,
        }, try ring.copy_cqe());
        try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer.len), buffer[0..]);
    }

    // Test with a non-zero offset

    registered_fds[fd_index] = -1;
    registered_fds[fd_index2] = -1;
    try ring.register_files_update(1, registered_fds[1..]);

    {
        // Next read should still work since fd_index in the registered file descriptors hasn't been updated yet.
        const sqe = try ring.read(0xcccccccc, fd_index, .{ .buffer = &buffer }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        sqe.flags |= linux.IOSQE_FIXED_FILE;

        try testing.expectEqual(@as(u32, 1), try ring.submit());
        try testing.expectEqual(linux.io_uring_cqe{
            .user_data = 0xcccccccc,
            .res = buffer.len,
            .flags = 0,
        }, try ring.copy_cqe());
        try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer.len), buffer[0..]);
    }

    try ring.register_files_update(0, registered_fds[0..]);

    {
        // Now this should fail since both fds are sparse (-1)
        const sqe = try ring.read(0xcccccccc, fd_index, .{ .buffer = &buffer }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        sqe.flags |= linux.IOSQE_FIXED_FILE;

        try testing.expectEqual(@as(u32, 1), try ring.submit());
        const cqe = try ring.copy_cqe();
        try testing.expectEqual(linux.E.BADF, cqe.err());
    }

    try ring.unregister_files();
}

test "shutdown" {
    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };

    // Socket bound, expect shutdown to work
    {
        const server = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
        defer _ = linux.close(server);
        try posix.setsockopt(server, posix.SOL.SOCKET, posix.SO.REUSEADDR, &mem.toBytes(@as(c_int, 1)));
        try bind(server, addrAny(&address), @sizeOf(linux.sockaddr.in));
        try listen(server, 1);

        // set address to the OS-chosen IP/port.
        var slen: posix.socklen_t = @sizeOf(linux.sockaddr.in);
        try getsockname(server, addrAny(&address), &slen);

        const shutdown_sqe = try ring.shutdown(0x445445445, server, linux.SHUT.RD);
        try testing.expectEqual(linux.IORING_OP.SHUTDOWN, shutdown_sqe.opcode);
        try testing.expectEqual(@as(i32, server), shutdown_sqe.fd);

        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            // This kernel's io_uring does not yet implement shutdown (kernel version < 5.11)
            .INVAL => return error.SkipZigTest,
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expectEqual(linux.io_uring_cqe{
            .user_data = 0x445445445,
            .res = 0,
            .flags = 0,
        }, cqe);
    }

    // Socket not bound, expect to fail with ENOTCONN
    {
        const server = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
        defer _ = linux.close(server);

        const shutdown_sqe = ring.shutdown(0x445445445, server, linux.SHUT.RD) catch |err| switch (err) {
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        };
        try testing.expectEqual(linux.IORING_OP.SHUTDOWN, shutdown_sqe.opcode);
        try testing.expectEqual(@as(i32, server), shutdown_sqe.fd);

        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        try testing.expectEqual(@as(u64, 0x445445445), cqe.user_data);
        try testing.expectEqual(linux.E.NOTCONN, cqe.err());
    }
}

test "renameat" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const old_path = "test_io_uring_renameat_old";
    const new_path = "test_io_uring_renameat_new";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Write old file with data

    const old_file = try tmp.dir.createFile(io, old_path, .{});
    defer old_file.close(io);
    try old_file.writeStreamingAll(io, "hello");

    // Submit renameat

    const sqe = try ring.renameat(
        0x12121212,
        tmp.dir.handle,
        old_path,
        tmp.dir.handle,
        new_path,
        0,
    );
    try testing.expectEqual(linux.IORING_OP.RENAMEAT, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(i32, tmp.dir.handle), @as(i32, @bitCast(sqe.len)));
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement renameat (kernel version < 5.11)
        .BADF, .INVAL => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = 0,
        .flags = 0,
    }, cqe);

    // Validate that the old file doesn't exist anymore
    try testing.expectError(error.FileNotFound, tmp.dir.openFile(io, old_path, .{}));

    // Validate that the new file exists with the proper content
    var new_file_data: [16]u8 = undefined;
    try testing.expectEqualStrings("hello", try tmp.dir.readFile(io, new_path, &new_file_data));
}

test "unlinkat" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const path = "test_io_uring_unlinkat";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    // Write old file with data

    const file = try tmp.dir.createFile(io, path, .{});
    defer file.close(io);

    // Submit unlinkat

    const sqe = try ring.unlinkat(
        0x12121212,
        tmp.dir.handle,
        path,
        0,
    );
    try testing.expectEqual(linux.IORING_OP.UNLINKAT, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement unlinkat (kernel version < 5.11)
        .BADF, .INVAL => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = 0,
        .flags = 0,
    }, cqe);

    // Validate that the file doesn't exist anymore
    _ = tmp.dir.openFile(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => {},
        else => std.debug.panic("unexpected error: {}", .{err}),
    };
}

test "mkdirat" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_mkdirat";

    // Submit mkdirat

    const sqe = try ring.mkdirat(
        0x12121212,
        tmp.dir.handle,
        path,
        0o0755,
    );
    try testing.expectEqual(linux.IORING_OP.MKDIRAT, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement mkdirat (kernel version < 5.15)
        .BADF, .INVAL => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = 0,
        .flags = 0,
    }, cqe);

    // Validate that the directory exist
    _ = try tmp.dir.openDir(io, path, .{});
}

test "symlinkat" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = "test_io_uring_symlinkat";
    const link_path = "test_io_uring_symlinkat_link";

    const file = try tmp.dir.createFile(io, path, .{});
    defer file.close(io);

    // Submit symlinkat

    const sqe = try ring.symlinkat(
        0x12121212,
        path,
        tmp.dir.handle,
        link_path,
    );
    try testing.expectEqual(linux.IORING_OP.SYMLINKAT, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement symlinkat (kernel version < 5.15)
        .BADF, .INVAL => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = 0,
        .flags = 0,
    }, cqe);

    // Validate that the symlink exist
    _ = try tmp.dir.openFile(io, link_path, .{});
}

test "linkat" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const first_path = "test_io_uring_linkat_first";
    const second_path = "test_io_uring_linkat_second";

    // Write file with data

    const first_file = try tmp.dir.createFile(io, first_path, .{});
    defer first_file.close(io);
    try first_file.writeStreamingAll(io, "hello");

    // Submit linkat

    const sqe = try ring.linkat(
        0x12121212,
        tmp.dir.handle,
        first_path,
        tmp.dir.handle,
        second_path,
        0,
    );
    try testing.expectEqual(linux.IORING_OP.LINKAT, sqe.opcode);
    try testing.expectEqual(@as(i32, tmp.dir.handle), sqe.fd);
    try testing.expectEqual(@as(i32, tmp.dir.handle), @as(i32, @bitCast(sqe.len)));
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    const cqe = try ring.copy_cqe();
    switch (cqe.err()) {
        .SUCCESS => {},
        // This kernel's io_uring does not yet implement linkat (kernel version < 5.15)
        .BADF, .INVAL => return error.SkipZigTest,
        else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
    }
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0x12121212,
        .res = 0,
        .flags = 0,
    }, cqe);

    // Validate the second file
    var second_file_data: [16]u8 = undefined;
    try testing.expectEqualStrings("hello", try tmp.dir.readFile(io, second_path, &second_file_data));
}

test "provide_buffers: read" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const file = try Io.Dir.openFileAbsolute(io, "/dev/zero", .{});
    defer file.close(io);

    const group_id = 1337;
    const buffer_id = 0;

    const buffer_len = 128;

    var buffers: [4][buffer_len]u8 = undefined;

    // Provide 4 buffers

    {
        const sqe = try ring.provide_buffers(0xcccccccc, @as([*]u8, @ptrCast(&buffers)), buffer_len, buffers.len, group_id, buffer_id);
        try testing.expectEqual(linux.IORING_OP.PROVIDE_BUFFERS, sqe.opcode);
        try testing.expectEqual(@as(i32, buffers.len), sqe.fd);
        try testing.expectEqual(@as(u32, buffers[0].len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            // Happens when the kernel is < 5.7
            .INVAL, .BADF => return error.SkipZigTest,
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xcccccccc), cqe.user_data);
    }

    // Do 4 reads which should consume all buffers

    var i: usize = 0;
    while (i < buffers.len) : (i += 1) {
        const sqe = try ring.read(0xdededede, file.handle, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        try testing.expectEqual(@as(i32, file.handle), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER);
        const used_buffer_id = cqe.flags >> 16;
        try testing.expect(used_buffer_id >= 0 and used_buffer_id <= 3);
        try testing.expectEqual(@as(i32, buffer_len), cqe.res);

        try testing.expectEqual(@as(u64, 0xdededede), cqe.user_data);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer_len), buffers[used_buffer_id][0..@as(usize, @intCast(cqe.res))]);
    }

    // This read should fail

    {
        const sqe = try ring.read(0xdfdfdfdf, file.handle, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        try testing.expectEqual(@as(i32, file.handle), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            // Expected
            .NOBUFS => {},
            .SUCCESS => std.debug.panic("unexpected success", .{}),
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xdfdfdfdf), cqe.user_data);
    }

    // Provide 1 buffer again

    // Deliberately put something we don't expect in the buffers
    @memset(mem.sliceAsBytes(&buffers), 42);

    const reprovided_buffer_id = 2;

    {
        _ = try ring.provide_buffers(0xabababab, @as([*]u8, @ptrCast(&buffers[reprovided_buffer_id])), buffer_len, 1, group_id, reprovided_buffer_id);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
    }

    // Final read which should work

    {
        const sqe = try ring.read(0xdfdfdfdf, file.handle, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.READ, sqe.opcode);
        try testing.expectEqual(@as(i32, file.handle), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER);
        const used_buffer_id = cqe.flags >> 16;
        try testing.expectEqual(used_buffer_id, reprovided_buffer_id);
        try testing.expectEqual(@as(i32, buffer_len), cqe.res);
        try testing.expectEqual(@as(u64, 0xdfdfdfdf), cqe.user_data);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer_len), buffers[used_buffer_id][0..@as(usize, @intCast(cqe.res))]);
    }
}

test "remove_buffers" {
    const io = testing.io;

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const file = try Io.Dir.openFileAbsolute(io, "/dev/zero", .{});
    defer file.close(io);

    const group_id = 1337;
    const buffer_id = 0;

    const buffer_len = 128;

    var buffers: [4][buffer_len]u8 = undefined;

    // Provide 4 buffers

    {
        _ = try ring.provide_buffers(0xcccccccc, @as([*]u8, @ptrCast(&buffers)), buffer_len, buffers.len, group_id, buffer_id);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .INVAL, .BADF => return error.SkipZigTest,
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xcccccccc), cqe.user_data);
    }

    // Remove 3 buffers

    {
        const sqe = try ring.remove_buffers(0xbababababa, 3, group_id);
        try testing.expectEqual(linux.IORING_OP.REMOVE_BUFFERS, sqe.opcode);
        try testing.expectEqual(@as(i32, 3), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xbababababa), cqe.user_data);
    }

    // This read should work

    {
        _ = try ring.read(0xdfdfdfdf, file.handle, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER);
        const used_buffer_id = cqe.flags >> 16;
        try testing.expect(used_buffer_id >= 0 and used_buffer_id < 4);
        try testing.expectEqual(@as(i32, buffer_len), cqe.res);
        try testing.expectEqual(@as(u64, 0xdfdfdfdf), cqe.user_data);
        try testing.expectEqualSlices(u8, &([_]u8{0} ** buffer_len), buffers[used_buffer_id][0..@as(usize, @intCast(cqe.res))]);
    }

    // Final read should _not_ work

    {
        _ = try ring.read(0xdfdfdfdf, file.handle, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            // Expected
            .NOBUFS => {},
            .SUCCESS => std.debug.panic("unexpected success", .{}),
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
    }
}

test "provide_buffers: accept/connect/send/recv" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const group_id = 1337;
    const buffer_id = 0;

    const buffer_len = 128;
    var buffers: [4][buffer_len]u8 = undefined;

    // Provide 4 buffers

    {
        const sqe = try ring.provide_buffers(0xcccccccc, @as([*]u8, @ptrCast(&buffers)), buffer_len, buffers.len, group_id, buffer_id);
        try testing.expectEqual(linux.IORING_OP.PROVIDE_BUFFERS, sqe.opcode);
        try testing.expectEqual(@as(i32, buffers.len), sqe.fd);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            // Happens when the kernel is < 5.7
            .INVAL => return error.SkipZigTest,
            // Happens on the kernel 5.4
            .BADF => return error.SkipZigTest,
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xcccccccc), cqe.user_data);
    }

    const socket_test_harness = try createSocketTestHarness(&ring);
    defer socket_test_harness.close();

    // Do 4 send on the socket

    {
        var i: usize = 0;
        while (i < buffers.len) : (i += 1) {
            _ = try ring.send(0xdeaddead, socket_test_harness.server, &([_]u8{'z'} ** buffer_len), 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());
        }

        var cqes: [4]linux.io_uring_cqe = undefined;
        try testing.expectEqual(@as(u32, 4), try ring.copy_cqes(&cqes, 4));
    }

    // Do 4 recv which should consume all buffers

    // Deliberately put something we don't expect in the buffers
    @memset(mem.sliceAsBytes(&buffers), 1);

    var i: usize = 0;
    while (i < buffers.len) : (i += 1) {
        const sqe = try ring.recv(0xdededede, socket_test_harness.client, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.RECV, sqe.opcode);
        try testing.expectEqual(@as(i32, socket_test_harness.client), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 0), sqe.rw_flags);
        try testing.expectEqual(@as(u32, linux.IOSQE_BUFFER_SELECT), sqe.flags);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER);
        const used_buffer_id = cqe.flags >> 16;
        try testing.expect(used_buffer_id >= 0 and used_buffer_id <= 3);
        try testing.expectEqual(@as(i32, buffer_len), cqe.res);

        try testing.expectEqual(@as(u64, 0xdededede), cqe.user_data);
        const buffer = buffers[used_buffer_id][0..@as(usize, @intCast(cqe.res))];
        try testing.expectEqualSlices(u8, &([_]u8{'z'} ** buffer_len), buffer);
    }

    // This recv should fail

    {
        const sqe = try ring.recv(0xdfdfdfdf, socket_test_harness.client, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.RECV, sqe.opcode);
        try testing.expectEqual(@as(i32, socket_test_harness.client), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 0), sqe.rw_flags);
        try testing.expectEqual(@as(u32, linux.IOSQE_BUFFER_SELECT), sqe.flags);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            // Expected
            .NOBUFS => {},
            .SUCCESS => std.debug.panic("unexpected success", .{}),
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
        try testing.expectEqual(@as(u64, 0xdfdfdfdf), cqe.user_data);
    }

    // Provide 1 buffer again

    const reprovided_buffer_id = 2;

    {
        _ = try ring.provide_buffers(0xabababab, @as([*]u8, @ptrCast(&buffers[reprovided_buffer_id])), buffer_len, 1, group_id, reprovided_buffer_id);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }
    }

    // Redo 1 send on the server socket

    {
        _ = try ring.send(0xdeaddead, socket_test_harness.server, &([_]u8{'w'} ** buffer_len), 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        _ = try ring.copy_cqe();
    }

    // Final recv which should work

    // Deliberately put something we don't expect in the buffers
    @memset(mem.sliceAsBytes(&buffers), 1);

    {
        const sqe = try ring.recv(0xdfdfdfdf, socket_test_harness.client, .{ .buffer_selection = .{ .group_id = group_id, .len = buffer_len } }, 0);
        try testing.expectEqual(linux.IORING_OP.RECV, sqe.opcode);
        try testing.expectEqual(@as(i32, socket_test_harness.client), sqe.fd);
        try testing.expectEqual(@as(u64, 0), sqe.addr);
        try testing.expectEqual(@as(u32, buffer_len), sqe.len);
        try testing.expectEqual(@as(u16, group_id), sqe.buf_index);
        try testing.expectEqual(@as(u32, 0), sqe.rw_flags);
        try testing.expectEqual(@as(u32, linux.IOSQE_BUFFER_SELECT), sqe.flags);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        const cqe = try ring.copy_cqe();
        switch (cqe.err()) {
            .SUCCESS => {},
            else => |errno| std.debug.panic("unhandled errno: {}", .{errno}),
        }

        try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER);
        const used_buffer_id = cqe.flags >> 16;
        try testing.expectEqual(used_buffer_id, reprovided_buffer_id);
        try testing.expectEqual(@as(i32, buffer_len), cqe.res);
        try testing.expectEqual(@as(u64, 0xdfdfdfdf), cqe.user_data);
        const buffer = buffers[used_buffer_id][0..@as(usize, @intCast(cqe.res))];
        try testing.expectEqualSlices(u8, &([_]u8{'w'} ** buffer_len), buffer);
    }
}

test "accept multishot" {
    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    const listener_socket = try createListenerSocket(&address);
    defer _ = linux.close(listener_socket);

    // submit multishot accept operation
    var addr: posix.sockaddr = undefined;
    var addr_len: posix.socklen_t = @sizeOf(@TypeOf(addr));
    const userdata: u64 = 0xaaaaaaaa;
    _ = try ring.accept_multishot(userdata, listener_socket, &addr, &addr_len, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    var nr: usize = 4; // number of clients to connect
    while (nr > 0) : (nr -= 1) {
        // connect client
        const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
        errdefer _ = linux.close(client);
        try connect(client, addrAny(&address), @sizeOf(linux.sockaddr.in));

        // test accept completion
        var cqe = try ring.copy_cqe();
        if (cqe.err() == .INVAL) return error.SkipZigTest;
        try testing.expect(cqe.res > 0);
        try testing.expect(cqe.user_data == userdata);
        try testing.expect(cqe.flags & linux.IORING_CQE_F_MORE > 0); // more flag is set

        _ = linux.close(client);
    }
}

test "accept/connect/send_zc/recv" {
    try skipKernelLessThan(.{ .major = 6, .minor = 0, .patch = 0 });

    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const socket_test_harness = try createSocketTestHarness(&ring);
    defer socket_test_harness.close();

    const buffer_send = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe };
    var buffer_recv = [_]u8{0} ** 10;

    // zero-copy send
    const sqe_send = try ring.send_zc(0xeeeeeeee, socket_test_harness.client, buffer_send[0..], 0, 0);
    sqe_send.flags |= linux.IOSQE_IO_LINK;
    _ = try ring.recv(0xffffffff, socket_test_harness.server, .{ .buffer = buffer_recv[0..] }, 0);
    try testing.expectEqual(@as(u32, 2), try ring.submit());

    var cqe_send = try ring.copy_cqe();
    // First completion of zero-copy send.
    // IORING_CQE_F_MORE, means that there
    // will be a second completion event / notification for the
    // request, with the user_data field set to the same value.
    // buffer_send must be keep alive until second cqe.
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xeeeeeeee,
        .res = buffer_send.len,
        .flags = linux.IORING_CQE_F_MORE,
    }, cqe_send);

    cqe_send, const cqe_recv = brk: {
        const cqe1 = try ring.copy_cqe();
        const cqe2 = try ring.copy_cqe();
        break :brk if (cqe1.user_data == 0xeeeeeeee) .{ cqe1, cqe2 } else .{ cqe2, cqe1 };
    };

    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xffffffff,
        .res = buffer_recv.len,
        .flags = cqe_recv.flags & linux.IORING_CQE_F_SOCK_NONEMPTY,
    }, cqe_recv);
    try testing.expectEqualSlices(u8, buffer_send[0..buffer_recv.len], buffer_recv[0..]);

    // Second completion of zero-copy send.
    // IORING_CQE_F_NOTIF in flags signals that kernel is done with send_buffer
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xeeeeeeee,
        .res = 0,
        .flags = linux.IORING_CQE_F_NOTIF,
    }, cqe_send);
}

test "accept_direct" {
    if (builtin.cpu.arch.isRISCV()) return error.SkipZigTest; // https://codeberg.org/ziglang/zig/issues/30854

    try skipKernelLessThan(.{ .major = 5, .minor = 19, .patch = 0 });

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();
    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };

    // register direct file descriptors
    var registered_fds = [_]linux.fd_t{-1} ** 2;
    try ring.register_files(registered_fds[0..]);

    const listener_socket = try createListenerSocket(&address);
    defer _ = linux.close(listener_socket);

    const accept_userdata: u64 = 0xaaaaaaaa;
    const read_userdata: u64 = 0xbbbbbbbb;
    const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe };

    for (0..2) |_| {
        for (registered_fds, 0..) |_, i| {
            var buffer_recv = [_]u8{0} ** 16;
            const buffer_send: []const u8 = data[0 .. data.len - i]; // make it different at each loop

            // submit accept, will chose registered fd and return index in cqe
            _ = try ring.accept_direct(accept_userdata, listener_socket, null, null, 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());

            // connect
            const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
            try connect(client, addrAny(&address), @sizeOf(linux.sockaddr.in));
            defer _ = linux.close(client);

            // accept completion
            const cqe_accept = try ring.copy_cqe();
            try testing.expectEqual(posix.E.SUCCESS, cqe_accept.err());
            const fd_index = cqe_accept.res;
            try testing.expect(fd_index < registered_fds.len);
            try testing.expect(cqe_accept.user_data == accept_userdata);

            // send data
            _ = try send(client, buffer_send, 0);

            // Example of how to use registered fd:
            // Submit receive to fixed file returned by accept (fd_index).
            // Fd field is set to registered file index, returned by accept.
            // Flag linux.IOSQE_FIXED_FILE must be set.
            const recv_sqe = try ring.recv(read_userdata, fd_index, .{ .buffer = &buffer_recv }, 0);
            recv_sqe.flags |= linux.IOSQE_FIXED_FILE;
            try testing.expectEqual(@as(u32, 1), try ring.submit());

            // accept receive
            const recv_cqe = try ring.copy_cqe();
            try testing.expect(recv_cqe.user_data == read_userdata);
            try testing.expect(recv_cqe.res == buffer_send.len);
            try testing.expectEqualSlices(u8, buffer_send, buffer_recv[0..buffer_send.len]);
        }
        // no more available fds, accept will get NFILE error
        {
            // submit accept
            _ = try ring.accept_direct(accept_userdata, listener_socket, null, null, 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());
            // connect
            const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
            try connect(client, addrAny(&address), @sizeOf(linux.sockaddr.in));
            defer _ = linux.close(client);
            // completion with error
            const cqe_accept = try ring.copy_cqe();
            try testing.expect(cqe_accept.user_data == accept_userdata);
            try testing.expectEqual(posix.E.NFILE, cqe_accept.err());
        }
        // return file descriptors to kernel
        try ring.register_files_update(0, registered_fds[0..]);
    }
    try ring.unregister_files();
}

test "accept_multishot_direct" {
    try skipKernelLessThan(.{ .major = 5, .minor = 19, .patch = 0 });

    if (builtin.cpu.arch == .riscv64) {
        // https://github.com/ziglang/zig/issues/25734
        return error.SkipZigTest;
    }

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };

    var registered_fds = [_]linux.fd_t{-1} ** 2;
    try ring.register_files(registered_fds[0..]);

    const listener_socket = try createListenerSocket(&address);
    defer _ = linux.close(listener_socket);

    const accept_userdata: u64 = 0xaaaaaaaa;

    for (0..2) |_| {
        // submit multishot accept
        // Will chose registered fd and return index of the selected registered file in cqe.
        _ = try ring.accept_multishot_direct(accept_userdata, listener_socket, null, null, 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit());

        for (registered_fds) |_| {
            // connect
            const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
            try connect(client, addrAny(&address), @sizeOf(linux.sockaddr.in));
            defer _ = linux.close(client);

            // accept completion
            const cqe_accept = try ring.copy_cqe();
            const fd_index = cqe_accept.res;
            try testing.expect(fd_index < registered_fds.len);
            try testing.expect(cqe_accept.user_data == accept_userdata);
            try testing.expect(cqe_accept.flags & linux.IORING_CQE_F_MORE > 0); // has more is set
        }
        // No more available fds, accept will get NFILE error.
        // Multishot is terminated (more flag is not set).
        {
            // connect
            const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
            try connect(client, addrAny(&address), @sizeOf(linux.sockaddr.in));
            defer _ = linux.close(client);
            // completion with error
            const cqe_accept = try ring.copy_cqe();
            try testing.expect(cqe_accept.user_data == accept_userdata);
            try testing.expectEqual(posix.E.NFILE, cqe_accept.err());
            try testing.expect(cqe_accept.flags & linux.IORING_CQE_F_MORE == 0); // has more is not set
        }
        // return file descriptors to kernel
        try ring.register_files_update(0, registered_fds[0..]);
    }
    try ring.unregister_files();
}

test "socket" {
    try skipKernelLessThan(.{ .major = 5, .minor = 19, .patch = 0 });

    var ring = IoUring.init(1, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    // prepare, submit socket operation
    _ = try ring.socket(0, linux.AF.INET, posix.SOCK.STREAM, 0, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());

    // test completion
    var cqe = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());
    const fd: linux.fd_t = @intCast(cqe.res);
    try testing.expect(fd > 2);

    _ = linux.close(fd);
}

test "socket_direct/socket_direct_alloc/close_direct" {
    try skipKernelLessThan(.{ .major = 5, .minor = 19, .patch = 0 });

    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var registered_fds = [_]linux.fd_t{-1} ** 3;
    try ring.register_files(registered_fds[0..]);

    // create socket in registered file descriptor at index 0 (last param)
    _ = try ring.socket_direct(0, linux.AF.INET, posix.SOCK.STREAM, 0, 0, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    var cqe_socket = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe_socket.err());
    try testing.expect(cqe_socket.res == 0);

    // create socket in registered file descriptor at index 1 (last param)
    _ = try ring.socket_direct(0, linux.AF.INET, posix.SOCK.STREAM, 0, 0, 1);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    cqe_socket = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe_socket.err());
    try testing.expect(cqe_socket.res == 0); // res is 0 when index is specified

    // create socket in kernel chosen file descriptor index (_alloc version)
    // completion res has index from registered files
    _ = try ring.socket_direct_alloc(0, linux.AF.INET, posix.SOCK.STREAM, 0, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    cqe_socket = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe_socket.err());
    try testing.expect(cqe_socket.res == 2); // returns registered file index

    // use sockets from registered_fds in connect operation
    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    const listener_socket = try createListenerSocket(&address);
    defer _ = linux.close(listener_socket);
    const accept_userdata: u64 = 0xaaaaaaaa;
    const connect_userdata: u64 = 0xbbbbbbbb;
    const close_userdata: u64 = 0xcccccccc;
    for (registered_fds, 0..) |_, fd_index| {
        // prepare accept
        _ = try ring.accept(accept_userdata, listener_socket, null, null, 0);
        // prepare connect with fixed socket
        const connect_sqe = try ring.connect(connect_userdata, @intCast(fd_index), addrAny(&address), @sizeOf(linux.sockaddr.in));
        connect_sqe.flags |= linux.IOSQE_FIXED_FILE; // fd is fixed file index
        // submit both
        try testing.expectEqual(@as(u32, 2), try ring.submit());
        // get completions
        var cqe_connect = try ring.copy_cqe();
        var cqe_accept = try ring.copy_cqe();
        // ignore order
        if (cqe_connect.user_data == accept_userdata and cqe_accept.user_data == connect_userdata) {
            const a = cqe_accept;
            const b = cqe_connect;
            cqe_accept = b;
            cqe_connect = a;
        }
        // test connect completion
        try testing.expect(cqe_connect.user_data == connect_userdata);
        try testing.expectEqual(posix.E.SUCCESS, cqe_connect.err());
        // test accept completion
        try testing.expect(cqe_accept.user_data == accept_userdata);
        try testing.expectEqual(posix.E.SUCCESS, cqe_accept.err());

        //  submit and test close_direct
        _ = try ring.close_direct(close_userdata, @intCast(fd_index));
        try testing.expectEqual(@as(u32, 1), try ring.submit());
        var cqe_close = try ring.copy_cqe();
        try testing.expect(cqe_close.user_data == close_userdata);
        try testing.expectEqual(posix.E.SUCCESS, cqe_close.err());
    }

    try ring.unregister_files();
}

test "openat_direct/close_direct" {
    try skipKernelLessThan(.{ .major = 5, .minor = 19, .patch = 0 });

    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    var registered_fds = [_]linux.fd_t{-1} ** 3;
    try ring.register_files(registered_fds[0..]);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const path = "test_io_uring_close_direct";
    const flags: linux.O = .{ .ACCMODE = .RDWR, .CREAT = true };
    const mode: posix.mode_t = 0o666;
    const user_data: u64 = 0;

    // use registered file at index 0 (last param)
    _ = try ring.openat_direct(user_data, tmp.dir.handle, path, flags, mode, 0);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    var cqe = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());
    try testing.expect(cqe.res == 0);

    // use registered file at index 1
    _ = try ring.openat_direct(user_data, tmp.dir.handle, path, flags, mode, 1);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    cqe = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());
    try testing.expect(cqe.res == 0); // res is 0 when we specify index

    // let kernel choose registered file index
    _ = try ring.openat_direct(user_data, tmp.dir.handle, path, flags, mode, linux.IORING_FILE_INDEX_ALLOC);
    try testing.expectEqual(@as(u32, 1), try ring.submit());
    cqe = try ring.copy_cqe();
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());
    try testing.expect(cqe.res == 2); // chosen index is in res

    // close all open file descriptors
    for (registered_fds, 0..) |_, fd_index| {
        _ = try ring.close_direct(user_data, @intCast(fd_index));
        try testing.expectEqual(@as(u32, 1), try ring.submit());
        var cqe_close = try ring.copy_cqe();
        try testing.expectEqual(posix.E.SUCCESS, cqe_close.err());
    }
    try ring.unregister_files();
}

test "ring mapped buffers recv" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    // init buffer group
    const group_id: u16 = 1; // buffers group id
    const buffers_count: u16 = 2; // number of buffers in buffer group
    const buffer_size: usize = 4; // size of each buffer in group
    var buf_grp = BufferGroup.init(
        &ring,
        testing.allocator,
        group_id,
        buffer_size,
        buffers_count,
    ) catch |err| switch (err) {
        // kernel older than 5.19
        error.ArgumentsInvalid => return error.SkipZigTest,
        else => return err,
    };
    defer buf_grp.deinit(testing.allocator);

    // create client/server fds
    const fds = try createSocketTestHarness(&ring);
    defer fds.close();

    // for random user_data in sqe/cqe
    var Rnd = std.Random.DefaultPrng.init(std.testing.random_seed);
    var rnd = Rnd.random();

    var round: usize = 4; // repeat send/recv cycle round times
    while (round > 0) : (round -= 1) {
        // client sends data
        const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe };
        {
            const user_data = rnd.int(u64);
            _ = try ring.send(user_data, fds.client, data[0..], 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());
            const cqe_send = try ring.copy_cqe();
            if (cqe_send.err() == .INVAL) return error.SkipZigTest;
            try testing.expectEqual(linux.io_uring_cqe{ .user_data = user_data, .res = data.len, .flags = 0 }, cqe_send);
        }
        var pos: usize = 0;

        // read first chunk
        const cqe1 = try buf_grp_recv_submit_get_cqe(&ring, &buf_grp, fds.server, rnd.int(u64));
        var buf = try buf_grp.get(cqe1);
        try testing.expectEqualSlices(u8, data[pos..][0..buf.len], buf);
        pos += buf.len;
        // second chunk
        const cqe2 = try buf_grp_recv_submit_get_cqe(&ring, &buf_grp, fds.server, rnd.int(u64));
        buf = try buf_grp.get(cqe2);
        try testing.expectEqualSlices(u8, data[pos..][0..buf.len], buf);
        pos += buf.len;

        // both buffers provided to the kernel are used so we get error
        // 'no more buffers', until we put buffers to the kernel
        {
            const user_data = rnd.int(u64);
            _ = try buf_grp.recv(user_data, fds.server, 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());
            const cqe = try ring.copy_cqe();
            try testing.expectEqual(user_data, cqe.user_data);
            try testing.expect(cqe.res < 0); // fail
            try testing.expectEqual(posix.E.NOBUFS, cqe.err());
            try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == 0); // IORING_CQE_F_BUFFER flags is set on success only
            try testing.expectError(error.NoBufferSelected, cqe.buffer_id());
        }

        // put buffers back to the kernel
        try buf_grp.put(cqe1);
        try buf_grp.put(cqe2);

        // read remaining data
        while (pos < data.len) {
            const cqe = try buf_grp_recv_submit_get_cqe(&ring, &buf_grp, fds.server, rnd.int(u64));
            buf = try buf_grp.get(cqe);
            try testing.expectEqualSlices(u8, data[pos..][0..buf.len], buf);
            pos += buf.len;
            try buf_grp.put(cqe);
        }
    }
}

test "ring mapped buffers multishot recv" {
    const io = testing.io;
    _ = io;

    var ring = IoUring.init(16, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    // init buffer group
    const group_id: u16 = 1; // buffers group id
    const buffers_count: u16 = 2; // number of buffers in buffer group
    const buffer_size: usize = 4; // size of each buffer in group
    var buf_grp = BufferGroup.init(
        &ring,
        testing.allocator,
        group_id,
        buffer_size,
        buffers_count,
    ) catch |err| switch (err) {
        // kernel older than 5.19
        error.ArgumentsInvalid => return error.SkipZigTest,
        else => return err,
    };
    defer buf_grp.deinit(testing.allocator);

    // create client/server fds
    const fds = try createSocketTestHarness(&ring);
    defer fds.close();

    // for random user_data in sqe/cqe
    var Rnd = std.Random.DefaultPrng.init(std.testing.random_seed);
    var rnd = Rnd.random();

    var round: usize = 4; // repeat send/recv cycle round times
    while (round > 0) : (round -= 1) {
        // client sends data
        const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0xa, 0xb, 0xc, 0xd, 0xe, 0xf };
        {
            const user_data = rnd.int(u64);
            _ = try ring.send(user_data, fds.client, data[0..], 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());
            const cqe_send = try ring.copy_cqe();
            if (cqe_send.err() == .INVAL) return error.SkipZigTest;
            try testing.expectEqual(linux.io_uring_cqe{ .user_data = user_data, .res = data.len, .flags = 0 }, cqe_send);
        }

        // start multishot recv
        var recv_user_data = rnd.int(u64);
        _ = try buf_grp.recv_multishot(recv_user_data, fds.server, 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit()); // submit

        // server reads data into provided buffers
        // there are 2 buffers of size 4, so each read gets only chunk of data
        // we read four chunks of 4, 4, 4, 4 bytes each
        var chunk: []const u8 = data[0..buffer_size]; // first chunk
        const cqe1 = try expect_buf_grp_cqe(&ring, &buf_grp, recv_user_data, chunk);
        try testing.expect(cqe1.flags & linux.IORING_CQE_F_MORE > 0);

        chunk = data[buffer_size .. buffer_size * 2]; // second chunk
        const cqe2 = try expect_buf_grp_cqe(&ring, &buf_grp, recv_user_data, chunk);
        try testing.expect(cqe2.flags & linux.IORING_CQE_F_MORE > 0);

        // both buffers provided to the kernel are used so we get error
        // 'no more buffers', until we put buffers to the kernel
        {
            const cqe = try ring.copy_cqe();
            try testing.expectEqual(recv_user_data, cqe.user_data);
            try testing.expect(cqe.res < 0); // fail
            try testing.expectEqual(posix.E.NOBUFS, cqe.err());
            try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == 0); // IORING_CQE_F_BUFFER flags is set on success only
            // has more is not set
            // indicates that multishot is finished
            try testing.expect(cqe.flags & linux.IORING_CQE_F_MORE == 0);
            try testing.expectError(error.NoBufferSelected, cqe.buffer_id());
        }

        // put buffers back to the kernel
        try buf_grp.put(cqe1);
        try buf_grp.put(cqe2);

        // restart multishot
        recv_user_data = rnd.int(u64);
        _ = try buf_grp.recv_multishot(recv_user_data, fds.server, 0);
        try testing.expectEqual(@as(u32, 1), try ring.submit()); // submit

        chunk = data[buffer_size * 2 .. buffer_size * 3]; // third chunk
        const cqe3 = try expect_buf_grp_cqe(&ring, &buf_grp, recv_user_data, chunk);
        try testing.expect(cqe3.flags & linux.IORING_CQE_F_MORE > 0);
        try buf_grp.put(cqe3);

        chunk = data[buffer_size * 3 ..]; // last chunk
        const cqe4 = try expect_buf_grp_cqe(&ring, &buf_grp, recv_user_data, chunk);
        try testing.expect(cqe4.flags & linux.IORING_CQE_F_MORE > 0);
        try buf_grp.put(cqe4);

        // cancel pending multishot recv operation
        {
            const cancel_user_data = rnd.int(u64);
            _ = try ring.cancel(cancel_user_data, recv_user_data, 0);
            try testing.expectEqual(@as(u32, 1), try ring.submit());

            // expect completion of cancel operation and completion of recv operation
            var cqe_cancel = try ring.copy_cqe();
            if (cqe_cancel.err() == .INVAL) return error.SkipZigTest;
            var cqe_recv = try ring.copy_cqe();
            if (cqe_recv.err() == .INVAL) return error.SkipZigTest;

            // don't depend on order of completions
            if (cqe_cancel.user_data == recv_user_data and cqe_recv.user_data == cancel_user_data) {
                const a = cqe_cancel;
                const b = cqe_recv;
                cqe_cancel = b;
                cqe_recv = a;
            }

            // Note on different kernel results:
            // on older kernel (tested with v6.0.16, v6.1.57, v6.2.12, v6.4.16)
            //   cqe_cancel.err() == .NOENT
            //   cqe_recv.err() == .NOBUFS
            // on kernel (tested with v6.5.0, v6.5.7)
            //   cqe_cancel.err() == .SUCCESS
            //   cqe_recv.err() == .CANCELED
            // Upstream reference: https://github.com/axboe/liburing/issues/984

            // cancel operation is success (or NOENT on older kernels)
            try testing.expectEqual(cancel_user_data, cqe_cancel.user_data);
            try testing.expect(cqe_cancel.err() == .NOENT or cqe_cancel.err() == .SUCCESS);

            // recv operation is failed with err CANCELED (or NOBUFS on older kernels)
            try testing.expectEqual(recv_user_data, cqe_recv.user_data);
            try testing.expect(cqe_recv.res < 0);
            try testing.expect(cqe_recv.err() == .NOBUFS or cqe_recv.err() == .CANCELED);
            try testing.expect(cqe_recv.flags & linux.IORING_CQE_F_MORE == 0);
        }
    }
}

test "copy_cqes with wrapping sq.cqes buffer" {
    var ring = IoUring.init(2, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    try testing.expectEqual(2, ring.sq.sqes.len);
    try testing.expectEqual(4, ring.cq.cqes.len);

    // submit 2 entries, receive 2 completions
    var cqes: [8]linux.io_uring_cqe = undefined;
    {
        for (0..2) |_| {
            const sqe = try ring.get_sqe();
            sqe.prep_timeout(&.{ .sec = 0, .nsec = 10000 }, 0, 0);
            try testing.expect(try ring.submit() == 1);
        }
        var cqe_count: u32 = 0;
        while (cqe_count < 2) {
            cqe_count += try ring.copy_cqes(&cqes, 2 - cqe_count);
        }
    }

    try testing.expectEqual(2, ring.cq.head.*);

    // sq.sqes len is 4, starting at position 2
    // every 4 entries submit wraps completion buffer
    // we are reading ring.cq.cqes at indexes 2,3,0,1
    for (1..1024) |i| {
        for (0..4) |_| {
            const sqe = try ring.get_sqe();
            sqe.prep_timeout(&.{ .sec = 0, .nsec = 10000 }, 0, 0);
            try testing.expect(try ring.submit() == 1);
        }
        var cqe_count: u32 = 0;
        while (cqe_count < 4) {
            cqe_count += try ring.copy_cqes(&cqes, 4 - cqe_count);
        }
        try testing.expectEqual(4, cqe_count);
        try testing.expectEqual(2 + 4 * i, ring.cq.head.*);
    }
}

test "bind/listen/connect" {
    if (builtin.cpu.arch == .s390x) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/25956

    var ring = IoUring.init(4, 0) catch |err| switch (err) {
        error.SystemOutdated => return error.SkipZigTest,
        error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };
    defer ring.deinit();

    const probe = ring.get_probe() catch return error.SkipZigTest;
    // LISTEN is higher required operation
    if (!probe.is_supported(.LISTEN)) return error.SkipZigTest;

    var addr: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    const proto: u32 = if (addr.family == linux.AF.UNIX) 0 else linux.IPPROTO.TCP;

    const listen_fd = brk: {
        // Create socket
        _ = try ring.socket(1, addr.family, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, proto, 0);
        try testing.expectEqual(1, try ring.submit());
        var cqe = try ring.copy_cqe();
        try testing.expectEqual(1, cqe.user_data);
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        const listen_fd: linux.fd_t = @intCast(cqe.res);
        try testing.expect(listen_fd > 2);

        // Prepare: set socket option * 2, bind, listen
        var optval: u32 = 1;
        (try ring.setsockopt(2, listen_fd, linux.SOL.SOCKET, linux.SO.REUSEADDR, mem.asBytes(&optval))).link_next();
        (try ring.setsockopt(3, listen_fd, linux.SOL.SOCKET, linux.SO.REUSEPORT, mem.asBytes(&optval))).link_next();
        (try ring.bind(4, listen_fd, addrAny(&addr), @sizeOf(linux.sockaddr.in), 0)).link_next();
        _ = try ring.listen(5, listen_fd, 1, 0);
        // Submit 4 operations
        try testing.expectEqual(4, try ring.submit());
        // Expect all to succeed
        for (2..6) |user_data| {
            cqe = try ring.copy_cqe();
            try testing.expectEqual(user_data, cqe.user_data);
            try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        }

        // Check that socket option is set
        optval = 0;
        _ = try ring.getsockopt(5, listen_fd, linux.SOL.SOCKET, linux.SO.REUSEADDR, mem.asBytes(&optval));
        try testing.expectEqual(1, try ring.submit());
        cqe = try ring.copy_cqe();
        try testing.expectEqual(5, cqe.user_data);
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        try testing.expectEqual(1, optval);

        // Read system assigned port into addr
        var addr_len: posix.socklen_t = @sizeOf(linux.sockaddr.in);
        try getsockname(listen_fd, addrAny(&addr), &addr_len);

        break :brk listen_fd;
    };

    const connect_fd = brk: {
        // Create connect socket
        _ = try ring.socket(6, addr.family, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, proto, 0);
        try testing.expectEqual(1, try ring.submit());
        const cqe = try ring.copy_cqe();
        try testing.expectEqual(6, cqe.user_data);
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        // Get connect socket fd
        const connect_fd: linux.fd_t = @intCast(cqe.res);
        try testing.expect(connect_fd > 2 and connect_fd != listen_fd);
        break :brk connect_fd;
    };

    // Prepare accept/connect operations
    _ = try ring.accept(7, listen_fd, null, null, 0);
    _ = try ring.connect(8, connect_fd, addrAny(&addr), @sizeOf(linux.sockaddr.in));
    try testing.expectEqual(2, try ring.submit());
    // Get listener accepted socket
    var accept_fd: posix.socket_t = 0;
    for (0..2) |_| {
        const cqe = try ring.copy_cqe();
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        if (cqe.user_data == 7) {
            accept_fd = @intCast(cqe.res);
        } else {
            try testing.expectEqual(8, cqe.user_data);
        }
    }
    try testing.expect(accept_fd > 2 and accept_fd != listen_fd and accept_fd != connect_fd);

    // Communicate
    try testSendRecv(&ring, connect_fd, accept_fd);
    try testSendRecv(&ring, accept_fd, connect_fd);

    // Shutdown and close all sockets
    for ([_]posix.socket_t{ connect_fd, accept_fd, listen_fd }) |fd| {
        (try ring.shutdown(9, fd, posix.SHUT.RDWR)).link_next();
        _ = try ring.close(10, fd);
        try testing.expectEqual(2, try ring.submit());
        for (0..2) |i| {
            const cqe = try ring.copy_cqe();
            try testing.expectEqual(posix.E.SUCCESS, cqe.err());
            try testing.expectEqual(9 + i, cqe.user_data);
        }
    }
}

// Prepare, submit recv and get cqe using buffer group.
fn buf_grp_recv_submit_get_cqe(
    ring: *IoUring,
    buf_grp: *BufferGroup,
    fd: linux.fd_t,
    user_data: u64,
) !linux.io_uring_cqe {
    // prepare and submit recv
    const sqe = try buf_grp.recv(user_data, fd, 0);
    try testing.expect(sqe.flags & linux.IOSQE_BUFFER_SELECT == linux.IOSQE_BUFFER_SELECT);
    try testing.expect(sqe.buf_index == buf_grp.group_id);
    try testing.expectEqual(@as(u32, 1), try ring.submit()); // submit
    // get cqe, expect success
    const cqe = try ring.copy_cqe();
    try testing.expectEqual(user_data, cqe.user_data);
    try testing.expect(cqe.res >= 0); // success
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());
    try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER); // IORING_CQE_F_BUFFER flag is set

    return cqe;
}

fn expect_buf_grp_cqe(
    ring: *IoUring,
    buf_grp: *BufferGroup,
    user_data: u64,
    expected: []const u8,
) !linux.io_uring_cqe {
    // get cqe
    const cqe = try ring.copy_cqe();
    try testing.expectEqual(user_data, cqe.user_data);
    try testing.expect(cqe.res >= 0); // success
    try testing.expect(cqe.flags & linux.IORING_CQE_F_BUFFER == linux.IORING_CQE_F_BUFFER); // IORING_CQE_F_BUFFER flag is set
    try testing.expectEqual(expected.len, @as(usize, @intCast(cqe.res)));
    try testing.expectEqual(posix.E.SUCCESS, cqe.err());

    // get buffer from pool
    const buffer_id = try cqe.buffer_id();
    const len = @as(usize, @intCast(cqe.res));
    const buf = buf_grp.get_by_id(buffer_id)[0..len];
    try testing.expectEqualSlices(u8, expected, buf);

    return cqe;
}

fn testSendRecv(ring: *IoUring, send_fd: posix.socket_t, recv_fd: posix.socket_t) !void {
    const buffer_send = "0123456789abcdf" ** 10;
    var buffer_recv: [buffer_send.len * 2]u8 = undefined;

    // 2 sends
    _ = try ring.send(1, send_fd, buffer_send, linux.MSG.WAITALL);
    _ = try ring.send(2, send_fd, buffer_send, linux.MSG.WAITALL);
    try testing.expectEqual(2, try ring.submit());
    for (0..2) |i| {
        const cqe = try ring.copy_cqe();
        try testing.expectEqual(1 + i, cqe.user_data);
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        try testing.expectEqual(buffer_send.len, @as(usize, @intCast(cqe.res)));
    }

    // receive
    var recv_len: usize = 0;
    while (recv_len < buffer_send.len * 2) {
        _ = try ring.recv(3, recv_fd, .{ .buffer = buffer_recv[recv_len..] }, 0);
        try testing.expectEqual(1, try ring.submit());
        const cqe = try ring.copy_cqe();
        try testing.expectEqual(3, cqe.user_data);
        try testing.expectEqual(posix.E.SUCCESS, cqe.err());
        recv_len += @intCast(cqe.res);
    }

    // inspect recv buffer
    try testing.expectEqualSlices(u8, buffer_send, buffer_recv[0..buffer_send.len]);
    try testing.expectEqualSlices(u8, buffer_send, buffer_recv[buffer_send.len..]);
}

/// Used for testing server/client interactions.
pub const SocketTestHarness = struct {
    listener: posix.socket_t,
    server: posix.socket_t,
    client: posix.socket_t,

    pub fn close(self: SocketTestHarness) void {
        _ = linux.close(self.client);
        _ = linux.close(self.listener);
    }
};

pub fn createSocketTestHarness(ring: *IoUring) !SocketTestHarness {
    // Create a TCP server socket
    var address: linux.sockaddr.in = .{
        .port = 0,
        .addr = @bitCast([4]u8{ 127, 0, 0, 1 }),
    };
    const listener_socket = try createListenerSocket(&address);
    errdefer _ = linux.close(listener_socket);

    // Submit 1 accept
    var accept_addr: posix.sockaddr = undefined;
    var accept_addr_len: posix.socklen_t = @sizeOf(@TypeOf(accept_addr));
    _ = try ring.accept(0xaaaaaaaa, listener_socket, &accept_addr, &accept_addr_len, 0);

    // Create a TCP client socket
    const client = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
    errdefer _ = linux.close(client);
    _ = try ring.connect(0xcccccccc, client, addrAny(&address), @sizeOf(linux.sockaddr.in));

    try testing.expectEqual(@as(u32, 2), try ring.submit());

    var cqe_accept = try ring.copy_cqe();
    if (cqe_accept.err() == .INVAL) return error.SkipZigTest;
    var cqe_connect = try ring.copy_cqe();
    if (cqe_connect.err() == .INVAL) return error.SkipZigTest;

    // The accept/connect CQEs may arrive in any order, the connect CQE will sometimes come first:
    if (cqe_accept.user_data == 0xcccccccc and cqe_connect.user_data == 0xaaaaaaaa) {
        const a = cqe_accept;
        const b = cqe_connect;
        cqe_accept = b;
        cqe_connect = a;
    }

    try testing.expectEqual(@as(u64, 0xaaaaaaaa), cqe_accept.user_data);
    if (cqe_accept.res <= 0) std.debug.print("\ncqe_accept.res={}\n", .{cqe_accept.res});
    try testing.expect(cqe_accept.res > 0);
    try testing.expectEqual(@as(u32, 0), cqe_accept.flags);
    try testing.expectEqual(linux.io_uring_cqe{
        .user_data = 0xcccccccc,
        .res = 0,
        .flags = 0,
    }, cqe_connect);

    // All good

    return SocketTestHarness{
        .listener = listener_socket,
        .server = cqe_accept.res,
        .client = client,
    };
}

fn createListenerSocket(address: *linux.sockaddr.in) !posix.socket_t {
    const kernel_backlog = 1;
    const listener_socket = try socket(address.family, posix.SOCK.STREAM | posix.SOCK.CLOEXEC, 0);
    errdefer _ = linux.close(listener_socket);

    try posix.setsockopt(listener_socket, posix.SOL.SOCKET, posix.SO.REUSEADDR, &mem.toBytes(@as(c_int, 1)));
    try bind(listener_socket, addrAny(address), @sizeOf(linux.sockaddr.in));
    try listen(listener_socket, kernel_backlog);

    // set address to the OS-chosen IP/port.
    var slen: posix.socklen_t = @sizeOf(linux.sockaddr.in);
    try getsockname(listener_socket, addrAny(address), &slen);

    return listener_socket;
}

/// For use in tests. Returns SkipZigTest if kernel version is less than required.
inline fn skipKernelLessThan(required: std.SemanticVersion) !void {
    var uts: linux.utsname = undefined;
    const res = linux.uname(&uts);
    switch (linux.errno(res)) {
        .SUCCESS => {},
        else => |errno| return posix.unexpectedErrno(errno),
    }

    const release = mem.sliceTo(&uts.release, 0);
    // Strips potential extra, as kernel version might not be semver compliant, example "6.8.9-300.fc40.x86_64"
    const extra_index = std.mem.indexOfAny(u8, release, "-+");
    const stripped = release[0..(extra_index orelse release.len)];
    // Make sure the input don't rely on the extra we just stripped
    try testing.expect(required.pre == null and required.build == null);

    var current = try std.SemanticVersion.parse(stripped);
    current.pre = null; // don't check pre field
    if (required.order(current) == .gt) return error.SkipZigTest;
}

fn addrAny(addr: *linux.sockaddr.in) *linux.sockaddr {
    return @ptrCast(addr);
}

fn socket(domain: u32, socket_type: u32, protocol: u32) !posix.socket_t {
    const rc = posix.system.socket(domain, socket_type, protocol);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        else => return error.SocketCreationFailure,
    }
}

fn bind(sock: posix.socket_t, addr: *const posix.sockaddr, len: posix.socklen_t) !void {
    switch (posix.errno(posix.system.bind(sock, addr, len))) {
        .SUCCESS => return,
        else => return error.BindFailure,
    }
}

fn listen(sock: posix.socket_t, backlog: u31) !void {
    switch (posix.errno(posix.system.listen(sock, backlog))) {
        .SUCCESS => return,
        else => return error.ListenFailure,
    }
}

fn getsockname(sock: posix.socket_t, addr: *posix.sockaddr, addrlen: *posix.socklen_t) !void {
    switch (posix.errno(posix.system.getsockname(sock, addr, addrlen))) {
        .SUCCESS => return,
        else => return error.GetSockNameFailure,
    }
}

fn send(sockfd: posix.socket_t, buf: []const u8, flags: u32) !usize {
    const rc = posix.system.sendto(sockfd, buf.ptr, buf.len, flags, null, 0);
    switch (posix.errno(rc)) {
        .SUCCESS => return @intCast(rc),
        else => return error.SendFailed,
    }
}

fn connect(sock: posix.socket_t, sock_addr: *const posix.sockaddr, len: posix.socklen_t) !void {
    while (true) switch (posix.errno(posix.system.connect(sock, sock_addr, len))) {
        .SUCCESS => return,
        .INTR => continue,
        else => return error.ConnectFailed,
    };
}
