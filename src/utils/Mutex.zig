// TODO: Remove after https://codeberg.org/ziglang/zig/issues/31912 was merged

// zig fmt: off

//! Mutex is a synchronization primitive which enforces atomic access to a
//! shared region of code known as the "critical section".
//!
//! It does this by blocking ensuring only one thread is in the critical
//! section at any given point in time by blocking the others.
//!
//! Mutex can be statically initialized and is at most `@sizeOf(u64)` large.
//! Use `lock()` or `tryLock()` to enter the critical section and `unlock()` to leave it.

const std = @import("std");
const builtin = @import("builtin");
const Mutex = @This();

impl: Impl = .{},

pub const init: Mutex = .{};

/// Tries to acquire the mutex without blocking the caller's thread.
/// Returns `false` if the calling thread would have to block to acquire it.
/// Otherwise, returns `true` and the caller should `unlock()` the Mutex to release it.
pub fn tryLock(self: *Mutex) bool {
	return self.impl.tryLock();
}

/// Acquires the mutex, blocking the caller's thread until it can.
/// It is undefined behavior if the mutex is already held by the caller's thread.
/// Once acquired, call `unlock()` on the Mutex to release it.
pub fn lock(self: *Mutex) void {
	self.impl.lock();
}

/// Releases the mutex which was previously acquired with `lock()` or `tryLock()`.
/// It is undefined behavior if the mutex is unlocked from a different thread that it was locked from.
pub fn unlock(self: *Mutex) void {
	self.impl.unlock();
}

const Impl = WindowsImpl;

/// SRWLOCK on windows is almost always faster than Futex solution.
/// It also implements an efficient Condition with requeue support for us.
const WindowsImpl = struct {
	srwlock: windows.SRWLOCK = .{},

	fn tryLock(self: *@This()) bool {
		return windows.ntdll.RtlTryAcquireSRWLockExclusive(&self.srwlock) != .FALSE;
	}

	fn lock(self: *@This()) void {
		windows.ntdll.RtlAcquireSRWLockExclusive(&self.srwlock);
	}

	fn unlock(self: *@This()) void {
		windows.ntdll.RtlReleaseSRWLockExclusive(&self.srwlock);
	}

	const windows = std.os.windows;
};
