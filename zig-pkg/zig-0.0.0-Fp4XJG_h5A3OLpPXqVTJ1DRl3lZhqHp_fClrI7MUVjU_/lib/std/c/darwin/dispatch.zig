// dispatch/base.h
pub const function_t = *const fn (?*anyopaque) callconv(.c) void;

// dispatch/object.h
pub const object_t = *_os_object_s;
pub const retain = dispatch_retain;
pub const release = dispatch_release;
pub const get_context = dispatch_get_context;
pub const set_context = dispatch_set_context;
pub const set_finalizer_f = dispatch_set_finalizer_f;
pub const activate = dispatch_activate;
pub const @"suspend" = dispatch_suspend;
pub const @"resume" = dispatch_resume;

const _os_object_s = opaque {
    pub const retain = dispatch_retain;
    pub const release = dispatch_release;
    pub const get_context = dispatch_get_context;
    pub const set_context = dispatch_set_context;
    pub const set_finalizer = dispatch_set_finalizer_f;
    pub const activate = dispatch_activate;
    pub const @"suspend" = dispatch_suspend;
    pub const @"resume" = dispatch_resume;
    pub const set_target_queue = dispatch_set_target_queue;
};
extern "c" fn dispatch_retain(object: object_t) void;
extern "c" fn dispatch_release(object: object_t) void;
extern "c" fn dispatch_get_context(object: object_t) ?*anyopaque;
extern "c" fn dispatch_set_context(object: object_t, context: ?*anyopaque) void;
extern "c" fn dispatch_set_finalizer_f(object: object_t, finalizer: ?function_t) void;
extern "c" fn dispatch_activate(object: object_t) void;
extern "c" fn dispatch_suspend(object: object_t) void;
extern "c" fn dispatch_resume(object: object_t) void;

// dispatch/once.h
pub const once_t = enum(isize) {
    init = 0,
    done = -1,
    _,

    pub inline fn once(predicate: *once_t, context: ?*anyopaque, function: function_t) void {
        if (predicate.* != .done) {
            @branchHint(.unlikely);
            once_f(predicate, context, function);
        } else asm volatile ("" ::: .{ .memory = true });
        switch (builtin.mode) {
            .Debug, .ReleaseSafe => {},
            .ReleaseFast, .ReleaseSmall => if (predicate.* != .done) unreachable,
        }
    }
};
pub const once_f = dispatch_once_f;

extern "c" fn dispatch_once_f(predicate: *once_t, context: ?*anyopaque, function: function_t) void;

// dispatch/queue.h
pub const queue_t = *queue_s;
pub const queue_global_t = queue_t;
pub const queue_serial_executor_t = queue_t;
pub const queue_serial_t = queue_t;
pub const queue_main_t = queue_serial_t;
pub const queue_concurrent_t = queue_t;
pub const async_f = dispatch_async_f;
pub const sync_f = dispatch_sync_f;
pub const async_and_wait_f = dispatch_async_and_wait_f;
pub const apply_f = dispatch_apply_f;
pub const get_current_queue = dispatch_get_current_queue;
pub inline fn get_main_queue() queue_main_t {
    return &_dispatch_main_q;
}
pub const queue_priority_t = enum(c_long) {
    HIGH = 2,
    DEFAULT = 0,
    LOW = -1,
    BACKGROUND = std.math.minInt(i16),
    _,
};
pub const get_global_queue = dispatch_get_global_queue;
pub const queue_attr_t = ?*queue_attr_s;
pub inline fn QUEUE_SERIAL() queue_attr_t {
    return null;
}
pub inline fn QUEUE_INACTIVE() queue_attr_t {
    return queue_attr_make_initially_inactive(QUEUE_SERIAL());
}
pub inline fn QUEUE_CONCURRENT() queue_attr_t {
    return &_dispatch_queue_attr_concurrent;
}
pub inline fn QUEUE_CONCURRENT_INACTIVE() queue_attr_t {
    return queue_attr_make_initially_inactive(QUEUE_CONCURRENT());
}
pub const queue_attr_make_initially_inactive = dispatch_queue_attr_make_initially_inactive;
pub const TARGET_QUEUE_DEFAULT: ?queue_t = null;
pub const queue_create_with_target = dispatch_queue_create_with_target;
pub const queue_create = dispatch_queue_create;
pub const CURRENT_QUEUE_LABEL: ?[*:0]const u8 = null;
pub const queue_get_label = dispatch_queue_get_label;
pub const main = dispatch_main;
pub const after_f = dispatch_after_f;

const queue_s = opaque {
    pub inline fn as_object(queue: queue_t) object_t {
        return @ptrCast(queue);
    }
    pub const async = async_f;
    pub const sync = sync_f;
    pub const async_and_wait = async_and_wait_f;
    pub const apply = apply_f;
    pub const get_current = get_current_queue;
    pub const get_main = get_main_queue;
    pub const get_global = get_global_queue;
    pub const TARGET_DEFAULT = TARGET_QUEUE_DEFAULT;
    pub const create_with_target = queue_create_with_target;
    pub const create = queue_create;
    pub const get_label = queue_get_label;
};
extern "c" fn dispatch_async_f(queue: queue_t, context: ?*anyopaque, work: function_t) void;
extern "c" fn dispatch_sync_f(queue: queue_t, context: ?*anyopaque, work: function_t) void;
extern "c" fn dispatch_async_and_wait_f(queue: queue_t, context: ?*anyopaque, work: function_t) void;
extern "c" fn dispatch_apply_f(iterations: usize, queue: ?queue_t, context: ?*anyopaque, work: *const fn (context: ?*anyopaque, iteration: usize) callconv(.c) void) void;
extern "c" fn dispatch_get_current_queue() queue_t;
extern "c" var _dispatch_main_q: queue_s;
extern "c" fn dispatch_get_global_queue(identifier: isize, flags: usize) queue_global_t;
const queue_attr_s = opaque {
    pub inline fn as_object(queue_attr: queue_attr_t) object_t {
        return @ptrCast(queue_attr);
    }
    pub const SERIAL = QUEUE_SERIAL;
    pub const INACTIVE = QUEUE_INACTIVE;
    pub const CONCURRENT = QUEUE_CONCURRENT;
    pub const CONCURRENT_INACTIVE = QUEUE_CONCURRENT_INACTIVE;
};
extern "c" var _dispatch_queue_attr_concurrent: queue_attr_s;
extern "c" fn dispatch_queue_attr_make_initially_inactive(attr: queue_attr_t) queue_attr_t;
extern "c" fn dispatch_queue_create_with_target(label: ?[*:0]const u8, attr: queue_attr_t, target: ?queue_t) ?queue_t;
extern "c" fn dispatch_queue_create(label: ?[*:0]const u8, attr: queue_attr_t) ?queue_t;
extern "c" fn dispatch_queue_get_label(queue: ?queue_t) [*:0]const u8;
extern "c" fn dispatch_set_target_queue(object: object_t, queue: ?queue_t) void;
extern "c" fn dispatch_main() noreturn;
extern "c" fn dispatch_after_f(when: time_t, queue: queue_t, context: ?*anyopaque, work: function_t) void;

// dispatch/semaphore.h
pub const semaphore_t = *semaphore_s;
pub const semaphore_create = dispatch_semaphore_create;
pub const semaphore_wait = dispatch_semaphore_wait;
pub const semaphore_signal = dispatch_semaphore_signal;

const semaphore_s = opaque {
    pub inline fn as_object(semaphore: semaphore_t) object_t {
        return @ptrCast(semaphore);
    }
    pub const create = semaphore_create;
    pub const wait = semaphore_wait;
    pub const signal = semaphore_signal;
};
extern "c" fn dispatch_semaphore_create(value: isize) ?semaphore_t;
extern "c" fn dispatch_semaphore_wait(dsema: semaphore_t, timeout: time_t) isize;
extern "c" fn dispatch_semaphore_signal(dsema: semaphore_t) isize;

// dispatch/source.h
pub const source_t = *source_s;
pub const source_type_t = *const source_type_s;
pub const SOURCE_TYPE_DATA_ADD = &_dispatch_source_type_data_add;
pub const SOURCE_TYPE_DATA_OR = &_dispatch_source_type_data_or;
pub const SOURCE_TYPE_DATA_REPLACE = &_dispatch_source_type_data_replace;
pub const SOURCE_TYPE_MACH_SEND = &_dispatch_source_type_mach_send;
pub const SOURCE_TYPE_MACH_RECV = &_dispatch_source_type_mach_recv;
pub const SOURCE_TYPE_MEMORYPRESSURE = &_dispatch_source_type_memorypressure;
pub const SOURCE_TYPE_PROC = &_dispatch_source_type_proc;
pub const SOURCE_TYPE_READ = &_dispatch_source_type_read;
pub const SOURCE_TYPE_SIGNAL = &_dispatch_source_type_signal;
pub const SOURCE_TYPE_TIMER = &_dispatch_source_type_timer;
pub const SOURCE_TYPE_VNODE = &_dispatch_source_type_vnode;
pub const SOURCE_TYPE_WRITE = &_dispatch_source_type_write;
pub const source_mach_send_flags_t = packed struct(usize) {
    DEAD: bool = false,
    unused1: @Int(.unsigned, @bitSizeOf(usize) - 1) = 0,
};
pub const source_mach_recv_flags_t = packed struct(usize) {
    unused0: @Int(.unsigned, @bitSizeOf(usize) - 0) = 0,
};
pub const source_memorypressure_flags_t = packed struct(usize) {
    NORMAL: bool = false,
    WARN: bool = false,
    CRITICAL: bool = false,
    unused3: @Int(.unsigned, @bitSizeOf(usize) - 3) = 0,
};
pub const source_proc_flags_t = packed struct(usize) {
    unused0: u27 = 0,
    SIGNAL: bool = false,
    unused28: u1 = 0,
    EXEC: bool = false,
    FORK: bool = false,
    EXIT: bool = false,
    unused32: @Int(.unsigned, @bitSizeOf(usize) - 32) = 0,
};
pub const source_vnode_flags_t = packed struct(usize) {
    DELETE: bool = false,
    WRITE: bool = false,
    EXTEND: bool = false,
    ATTRIB: bool = false,
    LINK: bool = false,
    RENAME: bool = false,
    REVOKE: bool = false,
    unused7: u1 = 0,
    FUNLOCK: bool = false,
    unused9: @Int(.unsigned, @bitSizeOf(usize) - 9) = 0,
};
pub const source_timer_flags_t = packed struct(usize) {
    STRICT: bool = false,
    unused1: @Int(.unsigned, @bitSizeOf(usize) - 1) = 0,
};
pub const source_flags_t = packed union(usize) {
    raw: usize,
    MACH_SEND: source_mach_send_flags_t,
    MACH_RECV: source_mach_recv_flags_t,
    MEMORYPRESSURE: source_memorypressure_flags_t,
    PROC: source_proc_flags_t,
    VNODE: source_vnode_flags_t,
    pub const none: source_flags_t = .{ .raw = 0 };
};
pub const source_create = dispatch_source_create;
pub const source_set_event_handler_f = dispatch_source_set_event_handler_f;
pub const source_set_cancel_handler_f = dispatch_source_set_cancel_handler_f;
pub const source_cancel = dispatch_source_cancel;
pub const source_testcancel = dispatch_source_testcancel;
pub const source_get_handle = dispatch_source_get_handle;
pub const source_get_mask = dispatch_source_get_mask;
pub const source_get_data = dispatch_source_get_data;
pub const source_merge_data = dispatch_source_merge_data;
pub const source_set_timer = dispatch_source_set_timer;
pub const source_set_registration_handler_f = dispatch_source_set_registration_handler_f;

const source_s = opaque {
    pub inline fn as_object(source: source_t) object_t {
        return @ptrCast(source);
    }
    pub const set_event_handler = source_set_event_handler_f;
    pub const set_cancel_handler = source_set_cancel_handler_f;
    pub const cancel = source_cancel;
    pub const testcancel = source_testcancel;
    pub const get_handle = source_get_handle;
    pub const get_mask = source_get_mask;
    pub const get_data = source_get_data;
    pub const merge_data = source_merge_data;
    pub const set_timer = source_set_timer;
    pub const set_registration_handler = source_set_registration_handler_f;
};
const source_type_s = opaque {
    pub const DATA_ADD = SOURCE_TYPE_DATA_ADD;
    pub const DATA_OR = SOURCE_TYPE_DATA_OR;
    pub const DATA_REPLACE = SOURCE_TYPE_DATA_REPLACE;
    pub const MACH_SEND = SOURCE_TYPE_MACH_SEND;
    pub const MACH_RECV = SOURCE_TYPE_MACH_RECV;
    pub const MEMORYPRESSURE = SOURCE_TYPE_MEMORYPRESSURE;
    pub const PROC = SOURCE_TYPE_PROC;
    pub const READ = SOURCE_TYPE_READ;
    pub const SIGNAL = SOURCE_TYPE_SIGNAL;
    pub const TIMER = SOURCE_TYPE_TIMER;
    pub const VNODE = SOURCE_TYPE_VNODE;
    pub const WRITE = SOURCE_TYPE_WRITE;
};
extern "c" const _dispatch_source_type_data_add: source_type_s;
extern "c" const _dispatch_source_type_data_or: source_type_s;
extern "c" const _dispatch_source_type_data_replace: source_type_s;
extern "c" const _dispatch_source_type_mach_send: source_type_s;
extern "c" const _dispatch_source_type_mach_recv: source_type_s;
extern "c" const _dispatch_source_type_memorypressure: source_type_s;
extern "c" const _dispatch_source_type_proc: source_type_s;
extern "c" const _dispatch_source_type_read: source_type_s;
extern "c" const _dispatch_source_type_signal: source_type_s;
extern "c" const _dispatch_source_type_timer: source_type_s;
extern "c" const _dispatch_source_type_vnode: source_type_s;
extern "c" const _dispatch_source_type_write: source_type_s;
extern "c" fn dispatch_source_create(type: source_type_t, handle: usize, mask: source_flags_t, queue: ?queue_t) ?source_t;
extern "c" fn dispatch_source_set_event_handler_f(source: source_t, handler: ?function_t) void;
extern "c" fn dispatch_source_set_cancel_handler_f(source: source_t, handler: ?function_t) void;
extern "c" fn dispatch_source_cancel(source: source_t) void;
extern "c" fn dispatch_source_testcancel(source: source_t) isize;
extern "c" fn dispatch_source_get_handle(source: source_t) usize;
extern "c" fn dispatch_source_get_mask(source: source_t) source_flags_t;
extern "c" fn dispatch_source_get_data(source: source_t) usize;
extern "c" fn dispatch_source_merge_data(source: source_t, value: usize) void;
extern "c" fn dispatch_source_set_timer(source: source_t, start: time_t, interval: u64, leeway: u64) void;
extern "c" fn dispatch_source_set_registration_handler_f(source: source_t, handler: ?function_t) void;

// dispatch/time.h
pub const time_t = enum(u64) {
    WALL_NOW = WALLTIME_NOW,
    NOW = TIME_NOW,
    FOREVER = TIME_FOREVER,
    _,

    pub const time = dispatch_time;
    pub const walltime = dispatch_walltime;
    pub const after = dispatch_after_f;
};
pub const WALLTIME_NOW = ~@as(u64, 1);
pub const TIME_NOW: u64 = 0;
pub const TIME_FOREVER = ~@as(u64, 0);
pub const time = dispatch_time;
pub const walltime = dispatch_walltime;

extern "c" fn dispatch_time(when: time_t, delta: i64) time_t;
extern "c" fn dispatch_walltime(when: ?*const std.c.timespec, delta: i64) time_t;

const builtin = @import("builtin");
const std = @import("std");
