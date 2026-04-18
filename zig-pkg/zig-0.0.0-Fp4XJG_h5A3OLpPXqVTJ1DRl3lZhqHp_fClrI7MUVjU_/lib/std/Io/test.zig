const builtin = @import("builtin");
const native_endian = builtin.cpu.arch.endian();

const std = @import("std");
const Io = std.Io;
const DefaultPrng = std.Random.DefaultPrng;
const mem = std.mem;
const fs = std.fs;
const File = std.Io.File;
const assert = std.debug.assert;

const testing = std.testing;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectError = std.testing.expectError;
const expectEqualStrings = std.testing.expectEqualStrings;
const tmpDir = std.testing.tmpDir;

test "write a file, read it, then delete it" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    var data: [1024]u8 = undefined;
    var prng = DefaultPrng.init(testing.random_seed);
    const random = prng.random();
    random.bytes(data[0..]);
    const tmp_file_name = "temp_test_file.txt";
    {
        var file = try tmp.dir.createFile(io, tmp_file_name, .{});
        defer file.close(io);

        var file_writer = file.writer(io, &.{});
        const st = &file_writer.interface;
        try st.print("begin", .{});
        try st.writeAll(&data);
        try st.print("end", .{});
        try st.flush();
    }

    {
        // Make sure the exclusive flag is honored.
        try expectError(File.OpenError.PathAlreadyExists, tmp.dir.createFile(io, tmp_file_name, .{ .exclusive = true }));
    }

    {
        var file = try tmp.dir.openFile(io, tmp_file_name, .{});
        defer file.close(io);

        const file_size = try file.length(io);
        const expected_file_size: u64 = "begin".len + data.len + "end".len;
        try expectEqual(expected_file_size, file_size);

        var file_buffer: [1024]u8 = undefined;
        var file_reader = file.reader(io, &file_buffer);
        const contents = try file_reader.interface.allocRemaining(testing.allocator, .limited(2 * 1024));
        defer testing.allocator.free(contents);

        try expect(mem.eql(u8, contents[0.."begin".len], "begin"));
        try expect(mem.eql(u8, contents["begin".len .. contents.len - "end".len], &data));
        try expect(mem.eql(u8, contents[contents.len - "end".len ..], "end"));
    }
    try tmp.dir.deleteFile(io, tmp_file_name);
}

test "File.Writer.seekTo" {
    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const io = testing.io;

    var data: [8192]u8 = undefined;
    @memset(&data, 0x55);

    const tmp_file_name = "temp_test_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    var fw = file.writerStreaming(io, &.{});

    try fw.interface.writeAll(&data);
    try expect(fw.logicalPos() == try file.length(io));
    try fw.seekTo(1234);
    try expect(fw.logicalPos() == 1234);
}

test "file discard" {
    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const io = testing.io;

    const tmp_file_name = "temp_test_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    var fw = file.writerStreaming(io, &.{});

    try fw.interface.writeAll("test");

    var fr = file.reader(io, &.{});
    const r = &fr.interface;

    try std.testing.expectEqual(error.EndOfStream, r.discardAll(1024));
    try fr.seekTo(0);
    try std.testing.expectEqual(4, fr.interface.discardRemaining());
}

test "File.setLength" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const tmp_file_name = "temp_test_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    var fw = file.writerStreaming(io, &.{});

    // Verify that the file size changes and the file offset is not moved
    try expect((try file.length(io)) == 0);
    try expect(fw.logicalPos() == 0);
    try file.setLength(io, 8192);
    try expect((try file.length(io)) == 8192);
    try expect(fw.logicalPos() == 0);
    try fw.seekTo(100);
    try file.setLength(io, 4096);
    try expect((try file.length(io)) == 4096);
    try expect(fw.logicalPos() == 100);
    try file.setLength(io, 0);
    try expect((try file.length(io)) == 0);
    try expect(fw.logicalPos() == 100);
}

test "legacy setLength" {
    // https://github.com/ziglang/zig/issues/20747 (open fd does not have write permission)
    if (builtin.os.tag == .wasi and builtin.link_libc) return error.SkipZigTest;
    if (builtin.cpu.arch.isMIPS64() and (builtin.abi == .gnuabin32 or builtin.abi == .muslabin32)) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/23806

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const file_name = "afile.txt";
    try tmp.dir.writeFile(io, .{ .sub_path = file_name, .data = "ninebytes" });
    const f = try tmp.dir.openFile(io, file_name, .{ .mode = .read_write });
    defer f.close(io);

    const initial_size = try f.length(io);
    var buffer: [32]u8 = undefined;
    var reader = f.reader(io, &.{});

    {
        try f.setLength(io, initial_size);
        try expectEqual(initial_size, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(initial_size, try reader.interface.readSliceShort(&buffer));
        try expectEqualStrings("ninebytes", buffer[0..@intCast(initial_size)]);
    }

    {
        const larger = initial_size + 4;
        try f.setLength(io, larger);
        try expectEqual(larger, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(larger, try reader.interface.readSliceShort(&buffer));
        try expectEqualStrings("ninebytes\x00\x00\x00\x00", buffer[0..@intCast(larger)]);
    }

    {
        const smaller = initial_size - 5;
        try f.setLength(io, smaller);
        try expectEqual(smaller, try f.length(io));
        try reader.seekTo(0);
        try expectEqual(smaller, try reader.interface.readSliceShort(&buffer));
        try expectEqualStrings("nine", buffer[0..@intCast(smaller)]);
    }

    try f.setLength(io, 0);
    try expectEqual(0, try f.length(io));
    try reader.seekTo(0);
    try expectEqual(0, try reader.interface.readSliceShort(&buffer));
}

test "setTimestamps" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    const tmp_file_name = "just_a_temporary_file.txt";
    var file = try tmp.dir.createFile(io, tmp_file_name, .{ .read = true });
    defer file.close(io);

    const stat_old = try file.stat(io);

    // Set atime and mtime to 5s before
    try file.setTimestamps(io, .{
        .access_timestamp = if (stat_old.atime) |atime| .{ .new = atime.subDuration(.fromSeconds(5)) } else .unchanged,
        .modify_timestamp = .{ .new = stat_old.mtime.subDuration(.fromSeconds(5)) },
    });
    const stat_new = try file.stat(io);
    // NetBSD with noatime will just not update the timestamp, and noatime is default in at least NetBSD 11+.
    if (builtin.os.tag != .netbsd) {
        if (stat_old.atime) |old_atime| try expect(stat_new.atime.?.nanoseconds < old_atime.nanoseconds);
    }
    try expect(stat_new.mtime.nanoseconds < stat_old.mtime.nanoseconds);
}

test "Group" {
    const io = testing.io;

    var group: Io.Group = .init;
    var results: [2]usize = undefined;

    group.async(io, count, .{ 1, 10, &results[0] });
    group.async(io, count, .{ 20, 30, &results[1] });

    try group.await(io);

    try testing.expectEqualSlices(usize, &.{ 45, 245 }, &results);
}

fn count(a: usize, b: usize, result: *usize) void {
    var sum: usize = 0;
    for (a..b) |i| {
        sum += i;
    }
    result.* = sum;
}

test "Group.cancel" {
    const global = struct {
        fn sleep(io: Io, result: *usize) Io.Cancelable!void {
            defer result.* = 1;
            io.sleep(.fromSeconds(100_000), .awake) catch |err| switch (err) {
                error.Canceled => |e| return e,
            };
        }

        fn sleepRecancel(io: Io, result: *usize) void {
            io.sleep(.fromSeconds(100_000), .awake) catch |err| switch (err) {
                error.Canceled => io.recancel(),
            };
            result.* = 1;
        }

        fn sleepUncancelable(io: Io, result: *usize) void {
            const old_prot = io.swapCancelProtection(.blocked);
            defer _ = io.swapCancelProtection(old_prot);
            // Short sleep interval, because this one won't be canceled (that's the point!).
            io.sleep(.fromMilliseconds(50), .awake) catch {};
            result.* = 1;
        }
    };

    const io = testing.io;

    var group: Io.Group = .init;
    var results: [5]usize = @splat(0);

    group.concurrent(io, global.sleep, .{ io, &results[0] }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    try group.concurrent(io, global.sleep, .{ io, &results[1] });
    try group.concurrent(io, global.sleepRecancel, .{ io, &results[2] });
    try group.concurrent(io, global.sleepUncancelable, .{ io, &results[3] });
    // Because this one doesn't block until canceled, it is safe to run asynchronously.
    group.async(io, global.sleepUncancelable, .{ io, &results[4] });

    group.cancel(io);

    try testing.expectEqualSlices(usize, &.{ 1, 1, 1, 1, 1 }, &results);
}

test "Group.concurrent" {
    const io = testing.io;

    var group: Io.Group = .init;
    defer group.cancel(io);
    var results: [2]usize = undefined;

    group.concurrent(io, count, .{ 1, 10, &results[0] }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try expect(builtin.single_threaded);
            return;
        },
    };

    group.concurrent(io, count, .{ 20, 30, &results[1] }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try expect(builtin.single_threaded);
            return;
        },
    };

    try group.await(io);

    try testing.expectEqualSlices(usize, &.{ 45, 245 }, &results);
}

test "Group materializes error.Cancel" {
    const S = struct {
        fn task() Io.Cancelable!void {
            return error.Canceled;
        }
    };

    const io = testing.io;

    var group: Io.Group = .init;

    group.async(io, S.task, .{});
    group.concurrent(io, S.task, .{}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try expect(builtin.single_threaded);
            return;
        },
    };

    try group.await(io);
}

test "Group task receives cancelation unknowingly" {
    const S = struct {
        io: Io,
        err: ?Io.Cancelable!void,

        fn task(s: *@This()) void {
            foo(s);
        }

        fn foo(s: *@This()) void {
            s.err = s.io.sleep(.fromSeconds(300), .awake);
        }
    };

    const io = testing.io;

    var group: Io.Group = .init;
    var result: S = .{ .io = io, .err = null };
    group.concurrent(io, S.task, .{&result}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => {
            try expect(builtin.single_threaded);
            return;
        },
    };
    group.cancel(io);

    try expectError(error.Canceled, result.err.?);
}

fn testQueue(comptime len: usize) !void {
    const io = testing.io;
    var buf: [len]usize = undefined;
    var queue: Io.Queue(usize) = .init(&buf);
    var begin: usize = 0;
    for (1..len + 1) |n| {
        const end = begin + n;
        for (begin..end) |i| try queue.putOne(io, i);
        for (begin..end) |i| try expect(try queue.getOne(io) == i);
        begin = end;
    }
}

test "Queue" {
    try testQueue(1);
    try testQueue(2);
    try testQueue(3);
    try testQueue(4);
    try testQueue(5);
}

test "Queue.close single-threaded" {
    const io = std.testing.io;

    var buf: [10]u8 = undefined;
    var queue: Io.Queue(u8) = .init(&buf);

    try queue.putAll(io, &.{ 0, 1, 2, 3, 4, 5, 6 });
    try expectEqual(3, try queue.put(io, &.{ 7, 8, 9, 10 }, 0)); // there is capacity for 3 more items

    var get_buf: [4]u8 = undefined;

    // Receive some elements before closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(0, get_buf[0]);
    try expectEqual(1, get_buf[1]);
    try expectEqual(2, get_buf[2]);
    try expectEqual(3, get_buf[3]);
    try expectEqual(4, try queue.getOne(io));

    // ...and add a couple more now there's space
    try queue.putAll(io, &.{ 20, 21 });

    queue.close(io);

    // Receive more elements *after* closing
    try expectEqual(4, try queue.get(io, &get_buf, 0));
    try expectEqual(5, get_buf[0]);
    try expectEqual(6, get_buf[1]);
    try expectEqual(7, get_buf[2]);
    try expectEqual(8, get_buf[3]);
    try expectEqual(9, try queue.getOne(io));

    // Cannot put anything while closed, even if the buffer has space
    try expectError(error.Closed, queue.putOne(io, 100));
    try expectError(error.Closed, queue.putAll(io, &.{ 101, 102 }));
    try expectError(error.Closed, queue.putUncancelable(io, &.{ 103, 104 }, 0));

    // Even if we ask for 3 items, the queue is closed, so we only get the last 2
    try expectEqual(2, try queue.get(io, &get_buf, 4));
    try expectEqual(20, get_buf[0]);
    try expectEqual(21, get_buf[1]);

    // The queue is now empty, so `get` should return `error.Closed` too
    try expectError(error.Closed, queue.getOne(io));
    try expectError(error.Closed, queue.get(io, &get_buf, 0));
    try expectError(error.Closed, queue.putUncancelable(io, &get_buf, 2));
}

test "Event" {
    const global = struct {
        fn waitAndRead(io: Io, event: *Io.Event, ptr: *const u32) Io.Cancelable!u32 {
            try event.wait(io);
            return ptr.*;
        }
    };

    const io = std.testing.io;

    var event: Io.Event = .unset;
    var buffer: u32 = undefined;

    {
        var future = io.concurrent(global.waitAndRead, .{ io, &event, &buffer }) catch |err| switch (err) {
            error.ConcurrencyUnavailable => return error.SkipZigTest,
        };

        buffer = 123;
        event.set(io);

        const result = try future.await(io);

        try std.testing.expectEqual(123, result);
    }

    event.reset();

    {
        var future = io.concurrent(global.waitAndRead, .{ io, &event, &buffer }) catch |err| switch (err) {
            error.ConcurrencyUnavailable => return error.SkipZigTest,
        };
        try std.testing.expectError(error.Canceled, future.cancel(io));
    }
}

test "recancel" {
    const global = struct {
        fn worker(io: Io) Io.Cancelable!void {
            var dummy_event: Io.Event = .unset;

            if (dummy_event.wait(io)) {
                return;
            } else |err| switch (err) {
                error.Canceled => io.recancel(),
            }

            // Now we expect to see `error.Canceled` again.
            return dummy_event.wait(io);
        }
    };

    const io = std.testing.io;
    var future = io.concurrent(global.worker, .{io}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    if (future.cancel(io)) {
        return error.UnexpectedSuccess; // both `wait` calls should have returned `error.Canceled`
    } else |err| switch (err) {
        error.Canceled => {},
    }
}

test "swapCancelProtection" {
    const global = struct {
        fn waitTwice(
            io: Io,
            event: *Io.Event,
        ) error{ Canceled, CanceledWhileProtected }!void {
            // Wait for `event` while protected from cancelation.
            {
                const old_prot = io.swapCancelProtection(.blocked);
                defer _ = io.swapCancelProtection(old_prot);
                event.wait(io) catch |err| switch (err) {
                    error.Canceled => return error.CanceledWhileProtected,
                };
            }
            // Reset the event (it will never be set again), and this time wait for it without protection.
            event.reset();
            _ = try event.wait(io);
        }
        fn sleepThenSet(io: Io, event: *Io.Event) !void {
            // Give `waitTwice` a chance to get canceled.
            try io.sleep(.fromMilliseconds(200), .awake);
            event.set(io);
        }
    };

    const io = std.testing.io;

    var event: Io.Event = .unset;

    var wait_future = io.concurrent(global.waitTwice, .{ io, &event }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer wait_future.cancel(io) catch {};

    var set_future = try io.concurrent(global.sleepThenSet, .{ io, &event });
    defer set_future.cancel(io) catch {};

    if (wait_future.cancel(io)) {
        return error.UnexpectedSuccess; // there was no `set` call to unblock the second `wait`
    } else |err| switch (err) {
        error.Canceled => {},
        error.CanceledWhileProtected => |e| return e,
    }

    // Because it reached the `set`, it should be too late for `sleepThenSet` to see `error.Canceled`.
    try set_future.cancel(io);
}

test "cancel futex wait" {
    const global = struct {
        fn blockUntilCanceled(io: Io) void {
            while (true) io.futexWait(u32, &0, 0) catch |err| switch (err) {
                error.Canceled => return,
            };
        }
    };

    const io = std.testing.io;

    var future = io.concurrent(global.blockUntilCanceled, .{io}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer future.cancel(io);

    // Give the task some time to start so that we cancel while it is blocked.
    try io.sleep(.fromMilliseconds(20), .awake);
}

test "cancel sleep" {
    const global = struct {
        fn blockUntilCanceled(io: Io) void {
            while (true) io.sleep(.fromSeconds(100_000), .awake) catch |err| switch (err) {
                error.Canceled => return,
            };
        }
    };

    const io = std.testing.io;

    var future = io.concurrent(global.blockUntilCanceled, .{io}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    defer future.cancel(io);

    // Give the task some time to start so that we cancel while it is blocked.
    try io.sleep(.fromMilliseconds(20), .awake);
}

test "tasks spawned in group after Group.cancel are canceled" {
    const global = struct {
        fn waitThenSpawn(io: Io, group: *Io.Group) void {
            _ = io.swapCancelProtection(.blocked);
            group.concurrent(io, blockUntilCanceled, .{io}) catch {};
            io.sleep(.fromMilliseconds(10), .awake) catch unreachable;
            group.concurrent(io, blockUntilCanceled, .{io}) catch {};
            group.async(io, blockUntilCanceled, .{io});
        }
        fn blockUntilCanceled(io: Io) Io.Cancelable!void {
            while (true) io.sleep(.fromSeconds(100_000), .awake) catch |err| switch (err) {
                error.Canceled => |e| return e,
            };
        }
    };

    const io = std.testing.io;

    var group: Io.Group = .init;
    defer group.cancel(io);

    group.concurrent(io, global.blockUntilCanceled, .{io}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    try io.sleep(.fromMilliseconds(10), .awake); // let that first sleep start up
    try group.concurrent(io, global.waitThenSpawn, .{ io, &group });
}

test "random" {
    const io = testing.io;

    var a: u64 = undefined;
    var b: u64 = undefined;
    var c: u64 = undefined;

    io.random(@ptrCast(&a));
    io.random(@ptrCast(&b));
    io.random(@ptrCast(&c));

    try expect(a ^ b ^ c != 0);
}

test "randomSecure" {
    const io = testing.io;

    var buf_a: [50]u8 = undefined;
    var buf_b: [50]u8 = undefined;
    try io.randomSecure(&buf_a);
    try io.randomSecure(&buf_b);
    // If this test fails the chance is significantly higher that there is a bug than
    // that two sets of 50 bytes were equal.
    try expect(!mem.eql(u8, &buf_a, &buf_b));
}

test "memory mapping" {
    if (builtin.cpu.arch == .hexagon) return error.SkipZigTest; // mmap returned EINVAL
    if (builtin.os.tag == .wasi and builtin.link_libc) {
        // https://github.com/ziglang/zig/issues/20747 (open fd does not have write permission)
        return error.SkipZigTest;
    }

    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "blah.txt",
        .data = "this is my data123",
    });

    {
        var file = try tmp.dir.openFile(io, "blah.txt", .{ .mode = .read_write });
        defer file.close(io);

        var mm = try file.createMemoryMap(io, .{ .len = "this is my data123".len });
        defer mm.destroy(io);

        try expectEqualStrings("this is my data123", mm.memory);
        mm.memory[4] = '9';
        mm.memory[7] = '9';

        try mm.write(io);
    }

    var buffer: [100]u8 = undefined;
    const updated_contents = try tmp.dir.readFile(io, "blah.txt", &buffer);
    try expectEqualStrings("this9is9my data123", updated_contents);

    {
        var file = try tmp.dir.openFile(io, "blah.txt", .{ .mode = .read_write });
        defer file.close(io);

        var mm = try file.createMemoryMap(io, .{
            .len = "this9is9my".len,
        });
        defer mm.destroy(io);

        try expectEqualStrings("this9is9my", mm.memory);

        // Cross a page boundary to require an actual remap.
        const new_len = std.heap.pageSize() * 2;
        mm.setLength(io, new_len) catch |err| switch (err) {
            error.OperationUnsupported => {
                mm.destroy(io);
                mm = try file.createMemoryMap(io, .{ .len = new_len });
            },
            else => |e| return e,
        };
        try mm.read(io);

        try expectEqualStrings("this9is9my data123\x00\x00", mm.memory[0.."this9is9my data123\x00\x00".len]);
    }
}

test "read from a file using Batch.awaitAsync API" {
    const io = testing.io;

    var tmp = tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{
        .sub_path = "eyes.txt",
        .data = "Heaven's been cheating the Hell out of me",
    });
    try tmp.dir.writeFile(io, .{
        .sub_path = "saviour.txt",
        .data = "Burn your thoughts, erase your will / to gods of suffering and tears",
    });

    var eyes_file = try tmp.dir.openFile(io, "eyes.txt", .{});
    defer eyes_file.close(io);

    var saviour_file = try tmp.dir.openFile(io, "saviour.txt", .{});
    defer saviour_file.close(io);

    var eyes_buf: [100]u8 = undefined;
    var saviour_buf: [100]u8 = undefined;
    var storage: [2]Io.Operation.Storage = undefined;
    var batch: Io.Batch = .init(&storage);

    // Tests add API because this provides coverage for both add and addAt.
    try testing.expectEqual(0, batch.add(.{ .file_read_streaming = .{
        .file = eyes_file,
        .data = &.{&eyes_buf},
    } }));
    try testing.expectEqual(1, batch.add(.{ .file_read_streaming = .{
        .file = saviour_file,
        .data = &.{&saviour_buf},
    } }));

    // This API is supposed to *always* work even if the target has no
    // concurrency primitives available.
    try batch.awaitAsync(io);

    while (batch.next()) |completion| {
        switch (completion.index) {
            0 => {
                const n = try completion.result.file_read_streaming;
                try expectEqualStrings(
                    "Heaven's been cheating the Hell out of me"[0..n],
                    eyes_buf[0..n],
                );
            },
            1 => {
                const n = try completion.result.file_read_streaming;
                try expectEqualStrings(
                    "Burn your thoughts, erase your will / to gods of suffering and tears"[0..n],
                    saviour_buf[0..n],
                );
            },
            else => return error.TestFailure,
        }
    }
}

test "Event smoke test" {
    const io = testing.io;

    var event: Io.Event = .unset;
    try testing.expectEqual(false, event.isSet());

    // make sure the event gets set
    event.set(io);
    try testing.expectEqual(true, event.isSet());

    // make sure the event gets unset again
    event.reset();
    try testing.expectEqual(false, event.isSet());

    // waits should timeout as there's no other thread to set the event
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .zero,
        .clock = .awake,
    } }));
    try testing.expectError(error.Timeout, event.waitTimeout(io, .{ .duration = .{
        .raw = .fromMilliseconds(1),
        .clock = .awake,
    } }));

    // set the event again and make sure waits complete
    event.set(io);
    try event.wait(io);
    try event.waitTimeout(io, .{ .duration = .{ .raw = .fromMilliseconds(1), .clock = .awake } });
    try testing.expectEqual(true, event.isSet());
}

test "Event signaling" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const Context = struct {
        in: Io.Event = .unset,
        out: Io.Event = .unset,
        value: usize = 0,

        fn input(self: *@This()) !void {
            // wait for the value to become 1
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 1);

            // bump the value and wake up output()
            self.value = 2;
            self.out.set(io);

            // wait for output to receive 2, bump the value and wake us up with 3
            try self.in.wait(io);
            self.in.reset();
            try testing.expectEqual(self.value, 3);

            // bump the value and wake up output() for it to see 4
            self.value = 4;
            self.out.set(io);
        }

        fn output(self: *@This()) !void {
            // start with 0 and bump the value for input to see 1
            try testing.expectEqual(self.value, 0);
            self.value = 1;
            self.in.set(io);

            // wait for input to receive 1, bump the value to 2 and wake us up
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 2);

            // bump the value to 3 for input to see (rhymes)
            self.value = 3;
            self.in.set(io);

            // wait for input to bump the value to 4 and receive no more (rhymes)
            try self.out.wait(io);
            self.out.reset();
            try testing.expectEqual(self.value, 4);
        }
    };

    var ctx = Context{};

    const thread = try std.Thread.spawn(.{}, Context.output, .{&ctx});
    defer thread.join();

    try ctx.input();
}

test "Event broadcast" {
    if (builtin.single_threaded) {
        // This test requires spawning threads.
        return error.SkipZigTest;
    }

    const io = testing.io;

    const num_threads = 10;
    const Barrier = struct {
        event: Io.Event = .unset,
        counter: std.atomic.Value(usize) = std.atomic.Value(usize).init(num_threads),

        fn wait(self: *@This()) !void {
            if (self.counter.fetchSub(1, .acq_rel) == 1) {
                self.event.set(io);
            }
            try self.event.wait(io);
        }
    };

    const Context = struct {
        start_barrier: Barrier = .{},
        finish_barrier: Barrier = .{},

        fn run(self: *@This()) !void {
            try self.start_barrier.wait();
            try self.finish_barrier.wait();
        }
    };

    var ctx = Context{};
    var threads: [num_threads - 1]std.Thread = undefined;

    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Context.run, .{&ctx});
    defer for (threads) |t| t.join();

    try ctx.run();
}

test "Select" {
    const S = struct {
        fn foo() bool {
            return true;
        }

        fn bar(io: Io) Io.Cancelable!void {
            try io.sleep(.fromSeconds(300), .awake);
        }

        fn baz() error{Ignored}!u8 {
            return 42;
        }
    };

    const io = testing.io;

    const U = union(enum) {
        foo: bool,
        bar: Io.Cancelable!void,
        baz: error{Ignored}!u8,
    };
    var buffer: [4]U = undefined;
    var select: Io.Select(U) = .init(io, &buffer);
    defer _ = select.cancel();

    select.async(.foo, S.foo, .{});
    select.concurrent(.bar, S.bar, .{io}) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };

    switch (try select.await()) {
        .foo => {},
        .bar => return error.TestFailed, // should be sleeping
        .baz => return error.TestFailed, // not called yet
    }
    select.async(.foo, S.foo, .{});
    select.async(.foo, S.foo, .{});

    var finished_buffer: [3]U = undefined;
    const finished = finished_buffer[0..try select.awaitMany(&finished_buffer, 2)];
    try testing.expectEqualSlices(U, &.{ .{ .foo = true }, .{ .foo = true } }, finished);

    select.async(.baz, S.baz, .{});

    const result = switch (try select.await()) {
        .baz => |n| try n,
        .foo => return error.TestFailed, // not called
        .bar => return error.TestFailed, // should be sleeping
    };

    try testing.expectEqual(42, result);
}

test "Select with empty buffer, no deadlock" {
    const S = struct {
        fn sleeper(io: Io, duration: Io.Duration) Io.Cancelable!void {
            try io.sleep(duration, .awake);
        }
    };

    const io = testing.io;

    const U = union(enum) {
        sleeper: Io.Cancelable!void,
    };
    var select: Io.Select(U) = .init(io, &.{});
    defer select.cancelDiscard();

    select.concurrent(.sleeper, S.sleeper, .{ io, .fromNanoseconds(1) }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    select.concurrent(.sleeper, S.sleeper, .{ io, .fromSeconds(600) }) catch |err| switch (err) {
        error.ConcurrencyUnavailable => return error.SkipZigTest,
    };
    assert((try select.await()) == .sleeper);
}

test "Select.cancel with no tasks, no deadlock" {
    const io = testing.io;

    const U = union(enum) {
        nothing: void,
        also_nothing: void,
    };
    var select: Io.Select(U) = .init(io, &.{});
    try expectEqual(null, select.cancel());
}
