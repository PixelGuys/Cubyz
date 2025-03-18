const builtin = @import("builtin");
const std = @import("std");

const main = @import("../main.zig");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

fn growCapacity(current: usize, minimum: usize) usize {
	var new = current;
	while(true) {
		new +|= new/2 + 8;
		if(new >= minimum)
			return new;
	}
}

pub fn List(comptime T: type) type {
	return struct {
		items: []T = &.{},
		capacity: usize = 0,
		allocator: NeverFailingAllocator,

		pub fn init(allocator: NeverFailingAllocator) @This() {
			return .{
				.allocator = allocator,
			};
		}

		pub fn initCapacity(allocator: NeverFailingAllocator, capacity: usize) @This() {
			return .{
				.items = allocator.alloc(T, capacity)[0..0],
				.capacity = capacity,
				.allocator = allocator,
			};
		}

		pub fn deinit(self: @This()) void {
			if(self.capacity != 0) {
				self.allocator.free(self.items.ptr[0..self.capacity]);
			}
		}

		pub fn clearAndFree(self: *@This()) void {
			self.deinit();
			self.* = .{.allocator = self.allocator};
		}

		pub fn clearRetainingCapacity(self: *@This()) void {
			self.items.len = 0;
		}

		pub fn shrinkAndFree(self: *@This(), newLen: usize) void {
			const result = self.allocator.realloc(self.items.ptr[0..self.capacity], newLen);
			self.items.ptr = result.ptr;
			self.capacity = result.len;
		}

		pub fn toOwnedSlice(self: *@This()) []T {
			const result = self.allocator.realloc(self.items.ptr[0..self.capacity], self.items.len);
			self.* = .{.allocator = self.allocator};
			return result;
		}

		pub fn ensureCapacity(self: *@This(), newCapacity: usize) void {
			std.debug.assert(newCapacity >= self.items.len);
			const newAllocation = self.allocator.realloc(self.items.ptr[0..self.capacity], newCapacity);
			self.items.ptr = newAllocation.ptr;
			self.capacity = newAllocation.len;
		}

		fn ensureFreeCapacity(self: *@This(), freeCapacity: usize) void {
			if(freeCapacity + self.items.len <= self.capacity) return;
			self.ensureCapacity(growCapacity(self.capacity, freeCapacity + self.items.len));
		}

		pub fn resizeAssumeCapacity(self: *@This(), new_len: usize) void {
			self.items.len = new_len;
			std.debug.assert(self.items.len <= self.capacity);
		}

		pub fn resize(self: *@This(), new_len: usize) void {
			self.ensureCapacity(new_len);
			self.items.len = new_len;
		}

		pub fn addOneAssumeCapacity(self: *@This()) *T {
			self.items.len += 1;
			std.debug.assert(self.items.len <= self.capacity);
			return &self.items[self.items.len - 1];
		}

		pub fn addOne(self: *@This()) *T {
			self.ensureFreeCapacity(1);
			return self.addOneAssumeCapacity();
		}

		pub fn addManyAssumeCapacity(self: *@This(), n: usize) []T {
			self.items.len += n;
			std.debug.assert(self.items.len <= self.capacity);
			return self.items[self.items.len - n ..];
		}

		pub fn addMany(self: *@This(), n: usize) []T {
			self.ensureFreeCapacity(n);
			return self.addManyAssumeCapacity(n);
		}

		pub fn appendAssumeCapacity(self: *@This(), elem: T) void {
			self.addOneAssumeCapacity().* = elem;
		}

		pub fn append(self: *@This(), elem: T) void {
			self.addOne().* = elem;
		}

		pub fn appendNTimesAssumeCapacity(self: *@This(), elem: T, n: usize) void {
			@memset(self.addManyAssumeCapacity(n), elem);
		}

		pub fn appendNTimes(self: *@This(), elem: T, n: usize) void {
			@memset(self.addMany(n), elem);
		}

		pub fn appendSliceAssumeCapacity(self: *@This(), elems: []const T) void {
			@memcpy(self.addManyAssumeCapacity(elems.len), elems);
		}

		pub fn appendSlice(self: *@This(), elems: []const T) void {
			@memcpy(self.addMany(elems.len), elems);
		}

		pub fn insertAssumeCapacity(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendAssumeCapacity(elem);
			_ = self.addOneAssumeCapacity();
			std.mem.copyBackwards(T, self.items[i + 1 ..], self.items[0 .. self.items.len - 1][i..]);
			self.items[i] = elem;
		}

		pub fn insert(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.append(elem);
			_ = self.addOne();
			std.mem.copyBackwards(T, self.items[i + 1 ..], self.items[0 .. self.items.len - 1][i..]);
			self.items[i] = elem;
		}

		pub fn insertSliceAssumeCapacity(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendSliceAssumeCapacity(elems);
			_ = self.addManyAssumeCapacity(elems.len);
			std.mem.copyBackwards(T, self.items[i + elems.len ..], self.items[0 .. self.items.len - elems.len][i..]);
			@memcpy(self.items[i..][0..elems.len], elems);
		}

		pub fn insertSlice(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendSlice(elems);
			_ = self.addMany(elems.len);
			std.mem.copyBackwards(T, self.items[i + elems.len ..], self.items[0 .. self.items.len - elems.len][i..]);
			@memcpy(self.items[i..][0..elems.len], elems);
		}

		pub fn swapRemove(self: *@This(), i: usize) T {
			const old = self.items[i];
			self.items[i] = self.items[self.items.len - 1];
			self.items.len -= 1;
			return old;
		}

		pub fn orderedRemove(self: *@This(), i: usize) T {
			const newlen = self.items.len - 1;
			const old = self.items[i];
			for(self.items[i..newlen], i + 1..) |*b, j| b.* = self.items[j];
			self.items.len = newlen;
			return old;
		}

		pub fn popOrNull(self: *@This()) ?T {
			if(self.items.len == 0) return null;
			const val = self.items[self.items.len - 1];
			self.items.len -= 1;
			return val;
		}

		pub fn pop(self: *@This()) T {
			return self.popOrNull() orelse unreachable;
		}

		pub fn replaceRange(self: *@This(), start: usize, len: usize, new_items: []const T) void {
			const after_range = start + len;
			const range = self.items[start..after_range];

			if(range.len == new_items.len)
				@memcpy(range[0..new_items.len], new_items)
			else if(range.len < new_items.len) {
				const first = new_items[0..range.len];
				const rest = new_items[range.len..];

				@memcpy(range[0..first.len], first);
				self.insertSlice(after_range, rest);
			} else {
				@memcpy(range[0..new_items.len], new_items);
				const after_subrange = start + new_items.len;

				for(self.items[after_range..], 0..) |item, i| {
					self.items[after_subrange..][i] = item;
				}

				self.items.len -= len - new_items.len;
			}
		}

		pub const Writer = if(T != u8)
			@compileError("The Writer interface is only defined for ArrayList(u8) " ++
				"but the given type is ArrayList(" ++ @typeName(T) ++ ")")
		else
			std.io.Writer(*@This(), error{}, appendWrite);

		pub fn writer(self: *@This()) Writer {
			return .{.context = self};
		}

		fn appendWrite(self: *@This(), m: []const u8) !usize {
			self.appendSlice(m);
			return m.len;
		}
	};
}

pub fn ListUnmanaged(comptime T: type) type {
	return struct {
		items: []T = &.{},
		capacity: usize = 0,

		pub fn initCapacity(allocator: NeverFailingAllocator, capacity: usize) @This() {
			return .{
				.items = allocator.alloc(T, capacity)[0..0],
				.capacity = capacity,
			};
		}

		pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			if(self.capacity != 0) {
				allocator.free(self.items.ptr[0..self.capacity]);
			}
		}

		pub fn clearAndFree(self: *@This(), allocator: NeverFailingAllocator) void {
			self.deinit(allocator);
			self.* = .{};
		}

		pub fn clearRetainingCapacity(self: *@This()) void {
			self.items.len = 0;
		}

		pub fn shrinkAndFree(self: *@This(), allocator: NeverFailingAllocator, newLen: usize) void {
			const result = allocator.realloc(self.items.ptr[0..self.capacity], newLen);
			self.items.ptr = result.ptr;
			self.capacity = result.len;
		}

		pub fn toOwnedSlice(self: *@This(), allocator: NeverFailingAllocator) []T {
			const result = allocator.realloc(self.items.ptr[0..self.capacity], self.items.len);
			self.* = .{};
			return result;
		}

		pub fn ensureCapacity(self: *@This(), allocator: NeverFailingAllocator, newCapacity: usize) void {
			std.debug.assert(newCapacity >= self.items.len);
			const newAllocation = allocator.realloc(self.items.ptr[0..self.capacity], newCapacity);
			self.items.ptr = newAllocation.ptr;
			self.capacity = newAllocation.len;
		}

		fn ensureFreeCapacity(self: *@This(), allocator: NeverFailingAllocator, freeCapacity: usize) void {
			if(freeCapacity + self.items.len <= self.capacity) return;
			self.ensureCapacity(allocator, growCapacity(self.capacity, freeCapacity + self.items.len));
		}

		pub fn resizeAssumeCapacity(self: *@This(), new_len: usize) void {
			self.items.len = new_len;
			std.debug.assert(self.items.len <= self.capacity);
		}

		pub fn resize(self: *@This(), allocator: NeverFailingAllocator, new_len: usize) void {
			self.ensureCapacity(allocator, new_len);
			self.items.len = new_len;
		}

		pub fn addOneAssumeCapacity(self: *@This()) *T {
			self.items.len += 1;
			std.debug.assert(self.items.len <= self.capacity);
			return &self.items[self.items.len - 1];
		}

		pub fn addOne(self: *@This(), allocator: NeverFailingAllocator) *T {
			self.ensureFreeCapacity(allocator, 1);
			return self.addOneAssumeCapacity();
		}

		pub fn addManyAssumeCapacity(self: *@This(), n: usize) []T {
			self.items.len += n;
			std.debug.assert(self.items.len <= self.capacity);
			return self.items[self.items.len - n ..];
		}

		pub fn addMany(self: *@This(), allocator: NeverFailingAllocator, n: usize) []T {
			self.ensureFreeCapacity(allocator, n);
			return self.addManyAssumeCapacity(n);
		}

		pub fn appendAssumeCapacity(self: *@This(), elem: T) void {
			self.addOneAssumeCapacity().* = elem;
		}

		pub fn append(self: *@This(), allocator: NeverFailingAllocator, elem: T) void {
			self.addOne(allocator).* = elem;
		}

		pub fn appendNTimesAssumeCapacity(self: *@This(), elem: T, n: usize) void {
			@memset(self.addManyAssumeCapacity(n), elem);
		}

		pub fn appendNTimes(self: *@This(), allocator: NeverFailingAllocator, elem: T, n: usize) void {
			@memset(self.addMany(allocator, n), elem);
		}

		pub fn appendSliceAssumeCapacity(self: *@This(), elems: []const T) void {
			@memcpy(self.addManyAssumeCapacity(elems.len), elems);
		}

		pub fn appendSlice(self: *@This(), allocator: NeverFailingAllocator, elems: []const T) void {
			@memcpy(self.addMany(allocator, elems.len), elems);
		}

		pub fn insertAssumeCapacity(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendAssumeCapacity(elem);
			_ = self.addOneAssumeCapacity();
			std.mem.copyBackwards(T, self.items[i + 1 ..], self.items[0 .. self.items.len - 1][i..]);
			self.items[i] = elem;
		}

		pub fn insert(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.append(elem);
			_ = self.addOne();
			std.mem.copyBackwards(T, self.items[i + 1 ..], self.items[0 .. self.items.len - 1][i..]);
			self.items[i] = elem;
		}

		pub fn insertSliceAssumeCapacity(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendSliceAssumeCapacity(elems);
			_ = self.addManyAssumeCapacity(elems.len);
			std.mem.copyBackwards(T, self.items[i + elems.len ..], self.items[0 .. self.items.len - elems.len][i..]);
			@memcpy(self.items[i..][0..elems.len], elems);
		}

		pub fn insertSlice(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.items.len);
			if(i == self.items.len) return self.appendSlice(elems);
			_ = self.addMany(elems.len);
			std.mem.copyBackwards(T, self.items[i + elems.len ..], self.items[0 .. self.items.len - elems.len][i..]);
			@memcpy(self.items[i..][0..elems.len], elems);
		}

		pub fn swapRemove(self: *@This(), i: usize) T {
			const old = self.items[i];
			self.items[i] = self.items[self.items.len - 1];
			self.items.len -= 1;
			return old;
		}

		pub fn orderedRemove(self: *@This(), i: usize) T {
			const newlen = self.items.len - 1;
			const old = self.items[i];
			for(self.items[i..newlen], i + 1..) |*b, j| b.* = self.items[j];
			self.items.len = newlen;
			return old;
		}

		pub fn popOrNull(self: *@This()) ?T {
			if(self.items.len == 0) return null;
			const val = self.items[self.items.len - 1];
			self.items.len -= 1;
			return val;
		}

		pub fn pop(self: *@This()) T {
			return self.popOrNull() orelse unreachable;
		}

		pub fn replaceRange(self: *@This(), start: usize, len: usize, new_items: []const T) void {
			const after_range = start + len;
			const range = self.items[start..after_range];

			if(range.len == new_items.len)
				@memcpy(range[0..new_items.len], new_items)
			else if(range.len < new_items.len) {
				const first = new_items[0..range.len];
				const rest = new_items[range.len..];

				@memcpy(range[0..first.len], first);
				self.insertSlice(after_range, rest);
			} else {
				@memcpy(range[0..new_items.len], new_items);
				const after_subrange = start + new_items.len;

				for(self.items[after_range..], 0..) |item, i| {
					self.items[after_subrange..][i] = item;
				}

				self.items.len -= len - new_items.len;
			}
		}

		pub const Writer = if(T != u8)
			@compileError("The Writer interface is only defined for ArrayList(u8) " ++
				"but the given type is ArrayList(" ++ @typeName(T) ++ ")")
		else
			std.io.Writer(*@This(), error{}, appendWrite);

		pub fn writer(self: *@This()) Writer {
			return .{.context = self};
		}

		fn appendWrite(self: *@This(), m: []const u8) !usize {
			self.appendSlice(m);
			return m.len;
		}
	};
}

/// Holds multiple arrays sequentially in memory.
/// Allows addressing and remove each subarray individually, as well as iterating through all of them at once.
pub fn MultiArray(T: type, Range: type) type {
	const size = @typeInfo(Range).@"enum".fields.len;
	std.debug.assert(@typeInfo(Range).@"enum".is_exhaustive);
	for(@typeInfo(Range).@"enum".fields) |field| {
		std.debug.assert(field.value < size);
	}
	return struct {
		offsets: [size + 1]usize = @splat(0),
		items: [*]T = undefined,
		capacity: usize = 0,

		pub fn initCapacity(allocator: NeverFailingAllocator, capacity: usize) @This() {
			return .{
				.items = allocator.alloc(T, capacity)[0..0],
				.capacity = capacity,
			};
		}

		pub fn deinit(self: @This(), allocator: NeverFailingAllocator) void {
			if(self.capacity != 0) {
				allocator.free(self.items[0..self.capacity]);
			}
		}

		pub fn clearAndFree(self: *@This(), allocator: NeverFailingAllocator) void {
			self.deinit(allocator);
			self.* = .{};
		}

		pub fn clearRetainingCapacity(self: *@This()) void {
			self.offsets = @splat(0);
		}

		pub fn ensureCapacity(self: *@This(), allocator: NeverFailingAllocator, newCapacity: usize) void {
			if(newCapacity <= self.capacity) return;
			const newAllocation = allocator.realloc(self.items[0..self.capacity], newCapacity);
			self.items = newAllocation.ptr;
			self.capacity = newAllocation.len;
		}

		pub fn addMany(self: *@This(), allocator: NeverFailingAllocator, n: usize) []T {
			self.ensureFreeCapacity(allocator, n);
			return self.addManyAssumeCapacity(n);
		}

		pub fn replaceRange(self: *@This(), allocator: NeverFailingAllocator, range: Range, elems: []const T) void {
			const i: usize = @intFromEnum(range);
			const oldLen = self.offsets[i + 1] - self.offsets[i];
			self.ensureCapacity(allocator, self.offsets[size] - oldLen + elems.len);
			const startIndex = self.offsets[i + 1];
			const newStartIndex = self.offsets[i + 1] - oldLen + elems.len;
			const endIndex = self.offsets[size];
			const newEndIndex = self.offsets[size] - oldLen + elems.len;
			if(newStartIndex > startIndex) {
				std.mem.copyBackwards(T, self.items[newStartIndex..newEndIndex], self.items[startIndex..endIndex]);
			} else {
				std.mem.copyForwards(T, self.items[newStartIndex..newEndIndex], self.items[startIndex..endIndex]);
			}
			@memcpy(self.items[self.offsets[i]..][0..elems.len], elems);
			for(self.offsets[i + 1 ..]) |*offset| {
				offset.* = offset.* - oldLen + elems.len;
			}
		}

		pub fn getRange(self: *@This(), range: Range) []T {
			const i: usize = @intFromEnum(range);
			const startIndex = self.offsets[i];
			const endIndex = self.offsets[i + 1];
			return self.items[startIndex..endIndex];
		}

		pub fn getEverything(self: *@This()) []T {
			return self.items[0..self.offsets[size]];
		}
	};
}

const page_size_min = std.heap.page_size_min;
const page_size_max = std.heap.page_size_max;
const pageSize = std.heap.pageSize;

fn reserveMemory(len: usize) [*]align(page_size_min) u8 {
	if(builtin.os.tag == .windows) {
		return @ptrCast(@alignCast(std.os.windows.VirtualAlloc(null, len, std.os.windows.MEM_RESERVE, std.os.windows.PAGE_READWRITE) catch |err| {
			std.log.err("Got error while reserving virtual memory of size {}: {s}", .{len, @errorName(err)});
			@panic("Out of Memory");
		}));
	} else {
		return (std.posix.mmap(null, len, std.posix.PROT.NONE, .{.TYPE = .PRIVATE, .ANONYMOUS = true, .NORESERVE = true}, -1, 0) catch |err| {
			std.log.err("Got error while reserving virtual memory of size {}: {s}", .{len, @errorName(err)});
			@panic("Out of Memory");
		}).ptr;
	}
}

fn commitMemory(start: [*]align(page_size_min) u8, len: usize) void {
	if(builtin.os.tag == .windows) {
		_ = std.os.windows.VirtualAlloc(start, len, std.os.windows.MEM_COMMIT, std.os.windows.PAGE_READWRITE) catch |err| {
			std.log.err("Got error while committing virtual memory of size {}: {s}.", .{len, @errorName(err)});
			@panic("Out of Memory");
		};
	} else {
		std.posix.mprotect(start[0..len], std.posix.PROT.READ | std.posix.PROT.WRITE) catch |err| {
			std.log.err("Got error while committing virtual memory of size {}: {s}.", .{len, @errorName(err)});
			@panic("Out of Memory");
		};
	}
}

fn releaseMemory(start: [*]align(page_size_min) u8, len: usize) void {
	if(builtin.os.tag == .windows) {
		std.os.windows.VirtualFree(start, 0, std.os.windows.MEM_RELEASE);
	} else {
		std.posix.munmap(start[0..len]);
	}
}

/// A list that reserves a continuous region of virtual memory without actually committing its pages.
/// This allows it to grow without ever invalidating pointers.
pub fn VirtualList(T: type, maxSize: u32) type {
	return struct {
		mem: [*]align(page_size_min) T,
		len: u32,
		committedCapacity: u32,

		fn maxSizeBytes() usize {
			return std.mem.alignForward(usize, @as(usize, maxSize)*@sizeOf(T), pageSize());
		}

		pub fn init() @This() {
			return .{
				.mem = @ptrCast(reserveMemory(maxSizeBytes())),
				.len = 0,
				.committedCapacity = 0,
			};
		}

		pub fn deinit(self: @This()) void {
			releaseMemory(@ptrCast(self.mem), maxSizeBytes());
		}

		pub fn items(self: *@This()) []T {
			return self.mem[0..self.len];
		}

		pub fn clearRetainingCapacity(self: *@This()) void {
			self.len = 0;
		}

		pub fn ensureCapacity(self: *@This(), newCapacity: usize) void {
			if(newCapacity > self.committedCapacity) {
				const alignedCapacity = std.mem.alignForward(usize, self.committedCapacity*@sizeOf(T), pageSize());
				const newAlignedCapacity = std.mem.alignForward(usize, newCapacity*@sizeOf(T), pageSize());

				commitMemory(@alignCast(@as([*]align(page_size_min) u8, @ptrCast(self.mem))[alignedCapacity..]), newAlignedCapacity - alignedCapacity);
				self.committedCapacity = @intCast(newAlignedCapacity/@sizeOf(T));
			}
		}

		fn ensureFreeCapacity(self: *@This(), freeCapacity: usize) void {
			if(freeCapacity + self.len <= self.committedCapacity) return;
			self.ensureCapacity(freeCapacity + self.len);
		}

		pub fn resizeAssumeCapacity(self: *@This(), new_len: usize) void {
			self.len = new_len;
			std.debug.assert(self.len <= self.committedCapacity);
		}

		pub fn resize(self: *@This(), new_len: usize) void {
			self.ensureCapacity(new_len);
			self.len = new_len;
		}

		pub fn addOneAssumeCapacity(self: *@This()) *T {
			self.len += 1;
			std.debug.assert(self.len <= self.committedCapacity);
			return &self.mem[self.len - 1];
		}

		pub fn addOne(self: *@This()) *T {
			self.ensureFreeCapacity(1);
			return self.addOneAssumeCapacity();
		}

		pub fn addManyAssumeCapacity(self: *@This(), n: usize) []T {
			self.len += n;
			std.debug.assert(self.len <= self.committedCapacity);
			return self.items()[self.len - n ..];
		}

		pub fn addMany(self: *@This(), n: usize) []T {
			self.ensureFreeCapacity(n);
			return self.addManyAssumeCapacity(n);
		}

		pub fn appendAssumeCapacity(self: *@This(), elem: T) void {
			self.addOneAssumeCapacity().* = elem;
		}

		pub fn append(self: *@This(), elem: T) void {
			self.addOne().* = elem;
		}

		pub fn appendNTimesAssumeCapacity(self: *@This(), elem: T, n: usize) void {
			@memset(self.addManyAssumeCapacity(n), elem);
		}

		pub fn appendNTimes(self: *@This(), elem: T, n: usize) void {
			@memset(self.addMany(n), elem);
		}

		pub fn appendSliceAssumeCapacity(self: *@This(), elems: []const T) void {
			@memcpy(self.addManyAssumeCapacity(elems.len), elems);
		}

		pub fn appendSlice(self: *@This(), elems: []const T) void {
			@memcpy(self.addMany(elems.len), elems);
		}

		pub fn insertAssumeCapacity(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.len);
			if(i == self.len) return self.appendAssumeCapacity(elem);
			_ = self.addOneAssumeCapacity();
			std.mem.copyBackwards(T, self.items()[i + 1 ..], self.items()[0 .. self.len - 1][i..]);
			self.mem[i] = elem;
		}

		pub fn insert(self: *@This(), i: usize, elem: T) void {
			std.debug.assert(i <= self.len);
			if(i == self.len) return self.append(elem);
			_ = self.addOne();
			std.mem.copyBackwards(T, self.items()[i + 1 ..], self.items()[0 .. self.len - 1][i..]);
			self.mem[i] = elem;
		}

		pub fn insertSliceAssumeCapacity(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.len);
			if(i == self.len) return self.appendSliceAssumeCapacity(elems);
			_ = self.addManyAssumeCapacity(elems.len);
			std.mem.copyBackwards(T, self.items()[i + elems.len ..], self.items()[0 .. self.len - elems.len][i..]);
			@memcpy(self.items()[i..][0..elems.len], elems);
		}

		pub fn insertSlice(self: *@This(), i: usize, elems: []const T) void {
			std.debug.assert(i <= self.len);
			if(i == self.len) return self.appendSlice(elems);
			_ = self.addMany(elems.len);
			std.mem.copyBackwards(T, self.items()[i + elems.len ..], self.items()[0 .. self.len - elems.len][i..]);
			@memcpy(self.items()[i..][0..elems.len], elems);
		}

		pub fn swapRemove(self: *@This(), i: usize) T {
			const old = self.items()[i];
			self.items()[i] = self.items()[self.len - 1];
			self.len -= 1;
			return old;
		}

		pub fn orderedRemove(self: *@This(), i: usize) T {
			const newlen = self.len - 1;
			const old = self.items()[i];
			for(self.items()[i..newlen], i + 1..) |*b, j| b.* = self.items()[j];
			self.len = newlen;
			return old;
		}

		pub fn popOrNull(self: *@This()) ?T {
			if(self.len == 0) return null;
			const val = self.items()[self.len - 1];
			self.len -= 1;
			return val;
		}

		pub fn pop(self: *@This()) T {
			return self.popOrNull() orelse unreachable;
		}

		pub fn replaceRange(self: *@This(), start: usize, len: usize, new_items: []const T) void {
			const after_range = start + len;
			const range = self.items()[start..after_range];

			if(range.len == new_items.len)
				@memcpy(range[0..new_items.len], new_items)
			else if(range.len < new_items.len) {
				const first = new_items[0..range.len];
				const rest = new_items[range.len..];

				@memcpy(range[0..first.len], first);
				self.insertSlice(after_range, rest);
			} else {
				@memcpy(range[0..new_items.len], new_items);
				const after_subrange = start + new_items.len;

				for(self.items()[after_range..], 0..) |item, i| {
					self.items()[after_subrange..][i] = item;
				}

				self.len -= len - new_items.len;
			}
		}

		pub const Writer = if(T != u8)
			@compileError("The Writer interface is only defined for ArrayList(u8) " ++
				"but the given type is ArrayList(" ++ @typeName(T) ++ ")")
		else
			std.io.Writer(*@This(), error{}, appendWrite);

		pub fn writer(self: *@This()) Writer {
			return .{.context = self};
		}

		fn appendWrite(self: *@This(), m: []const u8) !usize {
			self.appendSlice(m);
			return m.len;
		}
	};
}
