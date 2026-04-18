//! Stores and manages the queue of link tasks. Each task is either a `PrelinkTask` or a `ZcuTask`.
//!
//! There are two `std.Io.Queue`s, for prelink and ZCU tasks respectively. The compiler writes tasks
//! to these queues, and a single concurrent linker task receives and processes them. `Compilation`
//! is responsible for calling `finishPrelinkQueue` and `finishZcuQueue` once all relevant tasks
//! have been queued. All prelink tasks must be queued and completed before any ZCU tasks can be
//! processed.
//!
//! If concurrency is unavailable, the `enqueuePrelink` and `enqueueZcu` functions will instead run
//! the given tasks immediately---the queues are unused.
//!
//! If the codegen backend does not permit concurrency, then `Compilation` will call `finishZcuQueue`
//! early so that the concurrent linker task exists after prelink and ZCU tasks will run
//! non-concurrently in `enqueueZcu`.

/// This is the concurrent call to `runLinkTasks`. It may be set to non-`null` in `start`, and is
/// set to `null` by the main thread after it is canceled. It is not otherwise modified; as such, it
/// may be checked non-atomically. If a task is being queued and this is `null`, tasks must be run
/// eagerly.
future: ?std.Io.Future(void),

/// This is only used if `future == null` during prelink. In that case, it is used to ensure that
/// only one prelink task is run at a time.
prelink_mutex: std.Io.Mutex,

/// Only valid if `future != null`.
prelink_queue: std.Io.Queue(PrelinkTask),
/// Only valid if `future != null`.
zcu_queue: std.Io.Queue(ZcuTask),

/// The capacity of the task queue buffers.
pub const buffer_size = 512;

/// The initial `Queue` state, containing no tasks, expecting no prelink tasks, and with no running worker thread.
/// The `queued_prelink` field may be appended to before calling `start`.
pub const empty: Queue = .{
    .future = null,
    .prelink_mutex = .init,
    .prelink_queue = undefined, // set in `start` if needed
    .zcu_queue = undefined, // set in `start` if needed
};

pub fn cancel(q: *Queue, io: Io) void {
    if (q.future) |*f| {
        f.cancel(io);
        q.future = null;
    }
}

pub fn wait(q: *Queue, io: Io) void {
    if (q.future) |*f| {
        f.await(io);
        q.future = null;
    }
}

/// This is expected to be called exactly once, after which the caller must not directly access
/// `queued_prelink` any longer. This will spawn the link thread if necessary.
pub fn start(
    q: *Queue,
    comp: *Compilation,
    arena: Allocator,
) Allocator.Error!void {
    assert(q.future == null);
    q.prelink_queue = .init(try arena.alloc(PrelinkTask, buffer_size));
    q.zcu_queue = .init(try arena.alloc(ZcuTask, buffer_size));
    if (comp.io.concurrent(runLinkTasks, .{ q, comp })) |future| {
        // We will run link tasks concurrently.
        q.future = future;
    } else |err| switch (err) {
        error.ConcurrencyUnavailable => {
            // We will run link tasks on the main thread.
            q.prelink_queue = undefined;
            q.zcu_queue = undefined;
        },
    }
}

/// Enqueues all prelink tasks in `tasks`. Asserts that they were expected, i.e. that
/// the queue is not yet closed. Also asserts that `tasks.len` is not 0.
pub fn enqueuePrelink(q: *Queue, comp: *Compilation, tasks: []const PrelinkTask) Io.Cancelable!void {
    const io = comp.io;

    if (q.future != null) {
        q.prelink_queue.putAll(io, tasks) catch |err| switch (err) {
            error.Canceled => |e| return e,
            error.Closed => unreachable,
        };
    } else {
        try q.prelink_mutex.lock(io);
        defer q.prelink_mutex.unlock(io);
        for (tasks) |task| link.doPrelinkTask(comp, task);
    }
}

pub fn enqueueZcu(
    q: *Queue,
    comp: *Compilation,
    tid: Zcu.PerThread.Id,
    task: ZcuTask,
) Io.Cancelable!void {
    const io = comp.io;

    assert(tid == .main);

    if (q.future != null) {
        if (q.zcu_queue.putOne(io, task)) |_| {
            return;
        } else |err| switch (err) {
            error.Canceled => |e| return e,
            error.Closed => {
                // The linker is still processing prelink tasks. Wait for those
                // to finish, after which the linker task will exist, and ZCU
                // tasks will be run non-concurrently. This logic exists for
                // backends which do not support `Zcu.Feature.separate_thread`.
                q.wait(io);
            },
        }
    }

    link.doZcuTask(comp, tid, task);
}

pub fn finishPrelinkQueue(q: *Queue, comp: *Compilation) Io.Cancelable!void {
    if (q.future != null) {
        q.prelink_queue.close(comp.io);
        return;
    }
    // If linking non-concurrently, we must run prelink.
    prelink: {
        const lf = comp.bin_file orelse break :prelink;
        if (lf.post_prelink) break :prelink;

        if (lf.prelink()) |_| {
            lf.post_prelink = true;
        } else |err| switch (err) {
            error.OutOfMemory => comp.link_diags.setAllocFailure(),
            error.LinkFailure => {},
            error.Canceled => |e| return e,
        }
    }
}

pub fn finishZcuQueue(q: *Queue, comp: *Compilation) void {
    if (q.future != null) {
        q.zcu_queue.close(comp.io);
    }
}

fn runLinkTasks(q: *Queue, comp: *Compilation) void {
    const io = comp.io;
    const tid: Zcu.PerThread.Id = .acquire(io);
    defer tid.release(io);

    var have_idle_tasks = true;

    prelink_tasks: while (true) {
        var task_buf: [128]PrelinkTask = undefined;
        const limit: usize = if (have_idle_tasks) 0 else 1;
        const n = q.prelink_queue.get(io, &task_buf, limit) catch |err| switch (err) {
            error.Canceled => return,
            error.Closed => break :prelink_tasks,
        };
        if (n == 0) {
            assert(have_idle_tasks);
            have_idle_tasks = runIdleTask(comp, tid);
        } else for (task_buf[0..n]) |task| {
            link.doPrelinkTask(comp, task);
            have_idle_tasks = true;
        }
    }

    // We've finished the prelink tasks, so run prelink if necessary.
    if (comp.bin_file) |lf| {
        if (!lf.post_prelink) {
            if (lf.prelink()) |_| {
                lf.post_prelink = true;
            } else |err| switch (err) {
                error.OutOfMemory => comp.link_diags.setAllocFailure(),
                error.Canceled => @panic("TODO"),
                error.LinkFailure => {},
            }
        }
    }

    zcu_tasks: while (true) {
        var task_buf: [128]ZcuTask = undefined;
        const limit: usize = if (have_idle_tasks) 0 else 1;
        const n = q.zcu_queue.get(io, &task_buf, limit) catch |err| switch (err) {
            error.Canceled => return,
            error.Closed => break :zcu_tasks,
        };
        if (n == 0) {
            assert(have_idle_tasks);
            have_idle_tasks = runIdleTask(comp, tid);
        } else for (task_buf[0..n]) |task| {
            link.doZcuTask(comp, tid, task);
            have_idle_tasks = true;
        }
    }
}
fn runIdleTask(comp: *Compilation, tid: Zcu.PerThread.Id) bool {
    return link.doIdleTask(comp, tid) catch |err| switch (err) {
        error.OutOfMemory => have_more: {
            comp.link_diags.setAllocFailure();
            break :have_more false;
        },
        error.LinkFailure => false,
    };
}

const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const Compilation = @import("../Compilation.zig");
const InternPool = @import("../InternPool.zig");
const link = @import("../link.zig");
const PrelinkTask = link.PrelinkTask;
const Queue = @This();
const Zcu = @import("../Zcu.zig");
const ZcuTask = link.ZcuTask;
