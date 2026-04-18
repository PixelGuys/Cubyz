//! An unsigned integer that blocks the kernel thread if the number would
//! become negative.
//!
//! This API supports static initialization and does not require deinitialization.
const Semaphore = @This();

const builtin = @import("builtin");

const std = @import("../std.zig");
const Io = std.Io;
const testing = std.testing;

mutex: Io.Mutex = .init,
cond: Io.Condition = .init,
/// It is OK to initialize this field to any value.
permits: usize = 0,

pub fn wait(s: *Semaphore, io: Io) Io.Cancelable!void {
    try s.mutex.lock(io);
    defer s.mutex.unlock(io);
    while (s.permits == 0) try s.cond.wait(io, &s.mutex);
    s.permits -= 1;
    if (s.permits > 0) s.cond.signal(io);
}

pub fn waitUncancelable(s: *Semaphore, io: Io) void {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);
    while (s.permits == 0) s.cond.waitUncancelable(io, &s.mutex);
    s.permits -= 1;
    if (s.permits > 0) s.cond.signal(io);
}

pub fn post(s: *Semaphore, io: Io) void {
    s.mutex.lockUncancelable(io);
    defer s.mutex.unlock(io);

    s.permits += 1;
    s.cond.signal(io);
}

test Semaphore {
    if (builtin.single_threaded) return error.SkipZigTest;
    const io = testing.io;

    const TestContext = struct {
        sem: *Semaphore,
        n: *i32,
        fn worker(ctx: *@This()) !void {
            try ctx.sem.wait(io);
            ctx.n.* += 1;
            ctx.sem.post(io);
        }
    };
    const num_threads = 3;
    var sem: Semaphore = .{ .permits = 1 };
    var threads: [num_threads]std.Thread = undefined;
    var n: i32 = 0;
    var ctx = TestContext{ .sem = &sem, .n = &n };

    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, TestContext.worker, .{&ctx});
    for (threads) |t| t.join();
    try sem.wait(io);
    try testing.expect(n == num_threads);
}
