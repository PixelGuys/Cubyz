const builtin = @import("builtin");
const std = @import("std");

// This implementation is based on coz.h, which is a single-header 'library' for implementing coz integration for C.
// The original coz.h uses some macro garbage and makes some assumptions about the target platform, hence why translate-c was skipped in favor of just rewriting the whole thing in Zig.
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
		std.log.debug("Initialized state for profile counter " ++ internal_counter_state.myName ++ " which is at 0x{0x}", .{@intFromPtr(internal_counter_state.counter)});
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

// TODO(bluesillybeard): Coz does also support MacOS however I do not have the resources to test that, so it is not supported for now.
const coz_provider = blk: {
	if (builtin.os.tag == .linux) {
		break :blk linux_coz_provider;
	} else {
		break :blk dummy_coz_provider;
	}
};

const linux_coz_provider = struct {
	// This needs to be weak in case dlsym is not available.
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
			std.log.debug("Initialized getCounter function pointer, which is {}", .{getCounterFn});
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
		}
		if (postBlockFn != null) {
			postBlockFn.?(skip_delays_int);
		}
	}
};

const dummy_coz_provider = struct {
	pub fn getCounter(@"type": CozCounterType, name: [:0]const u8) ?*CozCounter {
		_ = @"type";
		_ = name;
		return null;
	}

	pub fn addDelays() void {}

	pub fn preBlock() void {}

	pub fn postBlock(skip_delays: bool) void {
		_ = skip_delays;
	}
};
