const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.coz);

// This implementation is based on coz.h, which is a single-header 'library' for implementing coz integration for C.
// The original coz.h is very C flavored and relies on macros, hence why translate-c was skipped in favor of just rewriting the whole thing in Zig.
// The original coz.h header is less than 200 lines of C code (most of which is C/C++ boilerplate garbage) so this is not much of an investment.

// This must be c_int in order to match the coz ABI
const CozCounterType = enum(c_int) {
	throughput = 1,
	begin = 2,
	end = 3,
};

const CozCounter = extern struct {
	count: usize,
	backoff: usize,
};

fn incrementCounter(comptime counterType: CozCounterType, comptime name: [:0]const u8) void {
	// The original C header used a static variable in order to cache the reference to the counter.
	// TODO: That functionality has been replicated here, however it might be worth re-considering?
	// The reason is as follows: it is not enforced or even documented in the original C header,
	//   but the name *must* be a constant at runtime, otherwise the (in my opinion, jank) cache trick will cause issues.
	// For our use case, there is no reason to not enforce the name being a constant at compile time.
	const internal_counter_state = struct {
		// This is required and forces the zig compiler to keep each name separate rather than merging their code.
		// Yes, I tried it, even in debug mode the functions are merged and coz does not work correctly without this hack.
		const myName = name;
		const myCounterType = counterType;
		var initialized = false;
		var counter: ?*CozCounter = null;
	};
	if (!internal_counter_state.initialized) {
		internal_counter_state.counter = coz_provider.getCounter(internal_counter_state.myCounterType, internal_counter_state.myName);
		internal_counter_state.initialized = true;
		log.info("Initialized state for profile counter " ++ internal_counter_state.myName ++ " which is at 0x{0x}", .{@intFromPtr(internal_counter_state.counter)});
	}
	if (internal_counter_state.counter != null) {
		// Confirmed: this does compile to `lock incq` instructions in x86_64
		_ = @atomicRmw(usize, &internal_counter_state.counter.?.count, .Add, 1, .monotonic);
		// TODO(bluesillybeard): _COZ_CHECK_DELAYS (only matters on MacOS)
	}
}

pub fn progressNamed(comptime name: [:0]const u8) void {
	incrementCounter(.throughput, name);
}

// TODO: how to implement progress()? (the non-named one that uses the callers line# as the name instead)

pub fn begin(comptime name: [:0]const u8) void {
	incrementCounter(.begin, name);
}

pub fn end(comptime name: [:0]const u8) void {
	incrementCounter(.end, name);
}

// Comment taken directly from coz.h:
// Custom synchronization support.
// Use these macros around blocking operations that Coz does not intercept
// (e.g., custom mutexes, futex-based locks, RocksDB internal synchronization).
//
//   COZ_PRE_BLOCK;                        // before blocking
//   my_custom_lock_acquire(&lock);
//   COZ_POST_BLOCK(1);                    // after blocking (1 = skip delays)
//
//   // Before potentially unblocking another thread:
//   COZ_CATCH_UP;
//   my_custom_lock_release(&lock);
//
// COZ_POST_BLOCK(skip_delays):
//   skip_delays=1 when woken by another thread (e.g., mutex acquired)
//   skip_delays=0 when the wake may have been spurious or timed out
pub fn preBlock() void {
	coz_provider.preBlock();
}

pub fn catchUp() void {
	coz_provider.addDelays();
}

pub fn postBlock(skip_delays: bool) void {
	coz_provider.postBlock(skip_delays);
}

const coz_provider = struct {
	// This needs to be weak in case dlsym is not available (such as on Windows)
	var dlsym: ?*const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque = @extern(?*const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque, .{
		.name = "dlsym",
		.linkage = .weak,
	});
	const rltdDefault: ?*anyopaque = null;

	var getCounterFn: ?*fn (CozCounterType, [*:0]const u8) callconv(.c) ?*CozCounter = null;
	var getCounterFnInitialized: bool = false;
	var addDelaysFn: ?*fn () callconv(.c) void = null;
	var addDelaysFnInitialized: bool = false;
	var preBlockFn: ?*fn () callconv(.c) void = null;
	var preBlockFnInitialized: bool = false;
	// use c_int instead of bool to match the C ABI.
	var postBlockFn: ?*fn (c_int) callconv(.c) void = null;
	var postBlockFnInitialized: bool = false;

	pub fn getCounter(@"type": CozCounterType, name: [*:0]const u8) ?*CozCounter {
		if (!getCounterFnInitialized) {
			if (dlsym != null) {
				getCounterFn = @ptrCast(@alignCast(dlsym.?(rltdDefault, "_coz_get_counter")));
			}
			getCounterFnInitialized = true;
			log.info("Initialized _coz_get_counter function pointer, which is {?}", .{getCounterFn});
		}
		if (getCounterFn != null) {
			return getCounterFn.?(@"type", name);
		} else {
			return null;
		}
	}

	pub fn addDelays() void {
		if (!addDelaysFnInitialized) {
			if (dlsym != null) {
				addDelaysFn = @ptrCast(@alignCast(dlsym.?(rltdDefault, "_coz_add_delays")));
			}
			addDelaysFnInitialized = true;
			log.info("Initialized _coz_add_delays function pointer, which is {?}", .{addDelaysFn});
		}
		if (addDelaysFn != null) {
			addDelaysFn.?();
		}
	}

	pub fn preBlock() void {
		if (!preBlockFnInitialized) {
			if (dlsym != null) {
				preBlockFn = @ptrCast(@alignCast(dlsym.?(rltdDefault, "_coz_pre_block")));
			}
			preBlockFnInitialized = true;
			log.info("Initialized _coz_pre_block function pointer, which is {?}", .{preBlockFn});
		}
		if (preBlockFn != null) {
			preBlockFn.?();
		}
	}

	pub fn postBlock(skip_delays: bool) void {
		const skip_delays_int: c_int = if (skip_delays) 1 else 0;
		if (!postBlockFnInitialized) {
			if (dlsym != null) {
				postBlockFn = @ptrCast(@alignCast(dlsym.?(rltdDefault, "_coz_post_block")));
			}
			postBlockFnInitialized = true;
			log.info("Initialized _coz_post_block function pointer, which is {?}", .{postBlockFn});
		}
		if (postBlockFn != null) {
			postBlockFn.?(skip_delays_int);
		}
	}
};

// A port of the sem_toy example from Coz
// This is for testing purposes to ensure that our mutex and futex implementations integrate into Coz properly.
// Below is the comment copied directly from sem_toy.cpp:

// This is the regression test for semaphore interposition. A thread blocked on
// a semaphore is not running, so it must not be charged for virtual delays
// inserted while it slept. Before libcoz wrapped sem_wait/semaphore_wait, the
// main thread -- the one that visits the progress point -- paid all of them on
// wake-up, and the profile came out with a slope near zero or negative
// (measured: +0.13 with R^2 0.01, and -0.57 with R^2 0.18) instead of the ~1.0
// this program should show.
//
// Both loops inline the same xorshift, so the expected result is a single hot
// line with a slope near 1.0: removing that work removes the program.

// Note: Zig is apparently much better about preserving line numbers for inline functions, as each line in xorshift show up in the profile as expected.

// This actually outlines an infuriating problem of Coz: it does not consider upstream callers of a line of code.
// In the original toy example, if xorshift is not inlined, the resulting profile just says "xorshift is slow" and doesn't even mention the blatant bottleneck.

const utils = @import("utils.zig");

const Mutex = utils.Mutex;
const Futex = utils.Futex;

inline fn xorshift1(v: u64) u64 {
	var value = v;
	value ^= value << 13;
	value ^= value >> 7;
	value ^= value << 17;
	return value;
}

inline fn xorshift2(v: u64) u64 {
	var value = v;
	value ^= value << 13;
	value ^= value >> 7;
	value ^= value << 17;
	return value;
}

const iterations = 40000000;

// For whatever unknown reason, volatile cannot be applied to a variable (I suppose it is intended for exclusively memory-mapped IO)
// Volatile is needed so the compiler doesn't optimize the entire benchmark into a noop (TODO: does zig have a better way to do that?)
var slow_sink: u64 = undefined;
var fast_sink: u64 = undefined;

var slow_sink_ptr: *volatile u64 = &slow_sink;
var fast_sink_ptr: *volatile u64 = &fast_sink;

var futex_holder: std.atomic.Value(u32) = std.atomic.Value(u32){.raw = 0};
var futex: *const std.atomic.Value(u32) = &futex_holder;

pub const heap = @import("utils/heap.zig");

pub const globalAllocator: heap.NeverFailingAllocator = if (builtin.is_test) heap.testingAllocator else heap.allocators.handledGpa.allocator();

var threadedIo: std.Io.Threaded = undefined;
var io: std.Io = threadedIo.io();

fn toy_futex_slow_work() ?*anyopaque {
	// TODO: make sure the compiler doesn't just hard-code the final result (I suspect it will)
	var acc: u64 = 0x9E3779B97F4A7C15;
	for (0..iterations) |_| {
		acc = xorshift1(acc);
	}
	slow_sink_ptr.* = acc;
	Futex.wake(futex, 1);
	return null;
}

fn toy_futex_fast_work() ?*anyopaque {
	// TODO: make sure the compiler doesn't just hard-code the final result (I suspect it will)
	var acc: u64 = 0x9E3779B97F4A7C15;
	for (0..iterations/2) |_| {
		acc = xorshift2(acc);
	}
	fast_sink_ptr.* = acc;
	Futex.wake(futex, 1);
	return null;
}

pub fn toy_futex() void {
	threadedIo = .init(globalAllocator.allocator, .{});
	defer threadedIo.deinit();

	const num_rounds = 1000;
	std.log.info("Started toy_futex", .{});
	for (0..num_rounds) |round| {
		var t1 = io.concurrent(toy_futex_slow_work, .{}) catch |e| {
			std.log.err("Error: {any}", .{e});
			return;
		};
		var t2 = io.concurrent(toy_futex_fast_work, .{}) catch |e| {
			std.log.err("Error: {any}", .{e});
			return;
		};
		Futex.wait(futex, 0);
		Futex.wait(futex, 0);
		_ = t1.await(io);
		_ = t2.await(io);
		progressNamed("toy_futex");
		std.log.info("Round {}", .{round});
	}
	std.log.info("Finished", .{});
}

pub fn toy_mutex() void {
	// TODO
}

pub fn main() void {
	toy_futex();
}
