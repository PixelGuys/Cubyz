const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const builtin = @import("builtin");

const main = @import("main.zig");

pub const file_monitor = @import("utils/file_monitor.zig");

pub const Compression = struct { // MARK: Compression
	pub fn deflate(allocator: NeverFailingAllocator, data: []const u8, level: std.compress.flate.deflate.Level) []u8 {
		var result = main.List(u8).init(allocator);
		var comp = std.compress.flate.compressor(result.writer(), .{.level = level}) catch unreachable;
		_ = comp.write(data) catch unreachable;
		comp.finish() catch unreachable;
		return result.toOwnedSlice();
	}

	pub fn inflateTo(buf: []u8, data: []const u8) !usize {
		var streamIn = std.io.fixedBufferStream(data);
		var decomp = std.compress.flate.decompressor(streamIn.reader());
		var streamOut = std.io.fixedBufferStream(buf);
		try decomp.decompress(streamOut.writer());
		return streamOut.getWritten().len;
	}

	pub fn pack(sourceDir: std.fs.Dir, writer: anytype) !void {
		var comp = try std.compress.flate.compressor(writer, .{});
		var walker = try sourceDir.walk(main.stackAllocator.allocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .file) {
				var relPath: []const u8 = entry.path;
				if(builtin.os.tag == .windows) { // I hate you
					const copy = main.stackAllocator.dupe(u8, relPath);
					std.mem.replaceScalar(u8, copy, '\\', '/');
					relPath = copy;
				}
				defer if(builtin.os.tag == .windows) {
					main.stackAllocator.free(relPath);
				};
				var len: [4]u8 = undefined;
				std.mem.writeInt(u32, &len, @as(u32, @intCast(relPath.len)), .big);
				_ = try comp.write(&len);
				_ = try comp.write(relPath);

				const fileData = try sourceDir.readFileAlloc(main.stackAllocator.allocator, relPath, std.math.maxInt(usize));
				defer main.stackAllocator.free(fileData);

				std.mem.writeInt(u32, &len, @as(u32, @intCast(fileData.len)), .big);
				_ = try comp.write(&len);
				_ = try comp.write(fileData);
			}
		}
		try comp.finish();
	}

	pub fn unpack(outDir: std.fs.Dir, input: []const u8) !void {
		var stream = std.io.fixedBufferStream(input);
		var decomp = std.compress.flate.decompressor(stream.reader());
		const reader = decomp.reader();
		const _data = try reader.readAllAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(_data);
		var data = _data;
		while(data.len != 0) {
			var len = std.mem.readInt(u32, data[0..4], .big);
			data = data[4..];
			const path = data[0..len];
			data = data[len..];
			len = std.mem.readInt(u32, data[0..4], .big);
			data = data[4..];
			const fileData = data[0..len];
			data = data[len..];

			var splitter = std.mem.splitBackwardsScalar(u8, path, '/');
			_ = splitter.first();
			try outDir.makePath(splitter.rest());
			try outDir.writeFile(.{.data = fileData, .sub_path = path});
		}
	}
};

/// Implementation of https://en.wikipedia.org/wiki/Alias_method
pub fn AliasTable(comptime T: type) type { // MARK: AliasTable
	return struct {
		const AliasData = struct {
			chance: u16,
			alias: u16,
		};
		items: []T,
		aliasData: []AliasData,
		ownsSlice: bool = false,

		fn initAliasData(self: *@This(), totalChance: f32, currentChances: []f32) void {
			const desiredChance = totalChance/@as(f32, @floatFromInt(self.aliasData.len));

			var lastOverfullIndex: u16 = 0;
			var lastUnderfullIndex: u16 = 0;
			outer: while(true) {
				while(currentChances[lastOverfullIndex] <= desiredChance) {
					lastOverfullIndex += 1;
					if(lastOverfullIndex == self.items.len)
						break :outer;
				}
				while(currentChances[lastUnderfullIndex] >= desiredChance) {
					lastUnderfullIndex += 1;
					if(lastUnderfullIndex == self.items.len)
						break :outer;
				}
				const delta = desiredChance - currentChances[lastUnderfullIndex];
				currentChances[lastUnderfullIndex] = desiredChance;
				currentChances[lastOverfullIndex] -= delta;
				self.aliasData[lastUnderfullIndex] = .{
					.alias = lastOverfullIndex,
					.chance = @intFromFloat(delta/desiredChance*std.math.maxInt(u16)),
				};
				if (currentChances[lastOverfullIndex] < desiredChance) {
					lastUnderfullIndex = @min(lastUnderfullIndex, lastOverfullIndex);
				}
			}
		}

		pub fn init(allocator: NeverFailingAllocator, items: []T) @This() {
			var self: @This() = .{
				.items = items,
				.aliasData = allocator.alloc(AliasData, items.len),
			};
			if(items.len == 0) return self;
			@memset(self.aliasData, AliasData{.chance = 0, .alias = 0});
			const currentChances = main.stackAllocator.alloc(f32, items.len);
			defer main.stackAllocator.free(currentChances);
			var totalChance: f32 = 0;
			for(items, 0..) |*item, i| {
				totalChance += item.chance;
				currentChances[i] = item.chance;
			}

			self.initAliasData(totalChance, currentChances);

			return self;
		}

		pub fn initFromContext(allocator: NeverFailingAllocator, slice: anytype) @This() {
			const items = allocator.alloc(T, slice.len);
			for(slice, items) |context, *result| {
				result.* = context.getItem();
			}
			var self: @This() = .{
				.items = items,
				.aliasData = allocator.alloc(AliasData, items.len),
				.ownsSlice = true,
			};
			if(items.len == 0) return self;
			@memset(self.aliasData, AliasData{.chance = 0, .alias = 0});
			const currentChances = main.stackAllocator.alloc(f32, items.len);
			defer main.stackAllocator.free(currentChances);
			var totalChance: f32 = 0;
			for(slice, 0..) |context, i| {
				totalChance += context.chance;
				currentChances[i] = context.chance;
			}

			self.initAliasData(totalChance, currentChances);

			return self;
		}

		pub fn deinit(self: *const @This(), allocator: NeverFailingAllocator) void {
			allocator.free(self.aliasData);
			if(self.ownsSlice) {
				allocator.free(self.items);
			}
		}

		pub fn sample(self: *const @This(), seed: *u64) *T {
			const initialIndex = main.random.nextIntBounded(u16, seed, @as(u16, @intCast(self.items.len)));
			if(main.random.nextInt(u16, seed) < self.aliasData[initialIndex].chance) {
				return &self.items[self.aliasData[initialIndex].alias];
			}
			return &self.items[initialIndex];
		}
	};
}

/// A list that is always sorted in ascending order based on T.lessThan(lhs, rhs).
pub fn SortedList(comptime T: type) type { // MARK: SortedList
	return struct {
		const Self = @This();

		ptr: [*]T = undefined,
		len: u32 = 0,
		capacity: u32 = 0,

		pub fn deinit(self: Self, allocator: NeverFailingAllocator) void {
			allocator.free(self.ptr[0..self.capacity]);
		}

		pub fn items(self: Self) []T {
			return self.ptr[0..self.len];
		}

		fn increaseCapacity(self: *Self, allocator: NeverFailingAllocator) void {
			const newSize = 8 + self.capacity*3/2;
			const newSlice = allocator.realloc(self.ptr[0..self.capacity], newSize);
			self.capacity = @intCast(newSlice.len);
			self.ptr = newSlice.ptr;
		}

		pub fn insertSorted(self: *Self, allocator: NeverFailingAllocator, object: T) void {
			if(self.len == self.capacity) {
				self.increaseCapacity(allocator);
			}
			var i = self.len;
			while(i != 0) { // Find the point to insert and move the rest out of the way.
				if(object.lessThan(self.ptr[i - 1])) {
					self.ptr[i] = self.ptr[i - 1];
				} else {
					break;
				}
				i -= 1;
			}
			self.len += 1;
			self.ptr[i] = object;
		}

		pub fn toOwnedSlice(self: *Self, allocator: NeverFailingAllocator) []T {
			const output = allocator.realloc(self.ptr[0..self.capacity], self.len);
			self.* = .{};
			return output;
		}
	};
}

pub fn Array2D(comptime T: type) type { // MARK: Array2D
	return struct {
		const Self = @This();
		mem: []T,
		width: u32,
		height: u32,

		pub fn init(allocator: NeverFailingAllocator, width: u32, height: u32) Self {
			return .{
				.mem = allocator.alloc(T, width*height),
				.width = width,
				.height = height,
			};
		}

		pub fn deinit(self: Self, allocator: NeverFailingAllocator) void {
			allocator.free(self.mem);
		}

		pub fn get(self: Self, x: usize, y: usize) T {
			std.debug.assert(x < self.width and y < self.height);
			return self.mem[x*self.height + y];
		}

		pub fn getRow(self: Self, x: usize) []T {
			std.debug.assert(x < self.width);
			return self.mem[x*self.height..][0..self.height];
		}

		pub fn set(self: Self, x: usize, y: usize, t: T) void {
			std.debug.assert(x < self.width and y < self.height);
			self.mem[x*self.height + y] = t;
		}

		pub fn ptr(self: Self, x: usize, y: usize) *T {
			std.debug.assert(x < self.width and y < self.height);
			return &self.mem[x*self.height + y];
		}
	};
}

pub fn Array3D(comptime T: type) type { // MARK: Array3D
	return struct {
		const Self = @This();
		mem: []T,
		width: u32,
		depth: u32,
		height: u32,

		pub fn init(allocator: NeverFailingAllocator, width: u32, depth: u32, height: u32) Self {
			return .{
				.mem = allocator.alloc(T, width*height*depth),
				.width = width,
				.depth = depth,
				.height = height,
			};
		}

		pub fn deinit(self: Self, allocator: NeverFailingAllocator) void {
			allocator.free(self.mem);
		}

		pub fn get(self: Self, x: usize, y: usize, z: usize) T {
			std.debug.assert(x < self.width and y < self.depth and z < self.height);
			return self.mem[(x*self.depth + y)*self.height + z];
		}

		pub fn set(self: Self, x: usize, y: usize, z: usize, t: T) void {
			std.debug.assert(x < self.width and y < self.depth and z < self.height);
			self.mem[(x*self.depth + y)*self.height + z] = t;
		}

		pub fn ptr(self: Self, x: usize, y: usize, z: usize) *T {
			std.debug.assert(x < self.width and y < self.depth and z < self.height);
			return &self.mem[(x*self.depth + y)*self.height + z];
		}
	};
}

pub fn CircularBufferQueue(comptime T: type) type { // MARK: CircularBufferQueue
	return struct {
		const Self = @This();
		mem: []T,
		mask: usize,
		startIndex: usize,
		endIndex: usize,
		allocator: NeverFailingAllocator,

		pub fn init(allocator: NeverFailingAllocator, initialCapacity: usize) Self {
			comptime std.debug.assert(@sizeOf(Self) <= 64);
			std.debug.assert(initialCapacity-1 & initialCapacity == 0 and initialCapacity > 0);
			return .{
				.mem = allocator.alloc(T, initialCapacity),
				.mask = initialCapacity-1,
				.startIndex = 0,
				.endIndex = 0,
				.allocator = allocator,
			};
		}

		pub fn deinit(self: Self) void {
			self.allocator.free(self.mem);
		}

		fn increaseCapacity(self: *Self) void {
			const newMem = self.allocator.alloc(T, self.mem.len*2);
			@memcpy(newMem[0..(self.mem.len - self.startIndex)], self.mem[self.startIndex..]);
			@memcpy(newMem[(self.mem.len - self.startIndex)..][0..self.endIndex], self.mem[0..self.endIndex]);
			self.startIndex = 0;
			self.endIndex = self.mem.len;
			self.allocator.free(self.mem);
			self.mem = newMem;
			self.mask = self.mem.len - 1;
		}

		pub fn enqueue(self: *Self, elem: T) void {
			self.mem[self.endIndex] = elem;
			self.endIndex = (self.endIndex + 1) & self.mask;
			if(self.endIndex == self.startIndex) {
				self.increaseCapacity();
			}
		}

		pub fn enqueue_back(self: *Self, elem: T) void {
			self.startIndex = (self.startIndex -% 1) & self.mask;
			self.mem[self.startIndex] = elem;
			if(self.endIndex == self.startIndex) {
				self.increaseCapacity();
			}
		}

		pub fn dequeue(self: *Self) ?T {
			if(self.empty()) return null;
			const result = self.mem[self.startIndex];
			self.startIndex = (self.startIndex + 1) & self.mask;
			return result;
		}

		pub fn dequeue_front(self: *Self) ?T {
			if(self.empty()) return null;
			self.endIndex = (self.endIndex -% 1) & self.mask;
			return self.mem[self.endIndex];
		}

		pub fn peek(self: *Self) ?T {
			if(self.empty()) return null;
			return self.mem[self.startIndex];
		}

		pub fn empty(self: *Self) bool {
			return self.startIndex == self.endIndex;
		}
	};
}

/// Basically just a regular queue with a mutex. TODO: Find a good lock-free implementation.
pub fn ConcurrentQueue(comptime T: type) type { // MARK: ConcurrentQueue
	return struct {
		const Self = @This();
		super: CircularBufferQueue(T),
		mutex: std.Thread.Mutex = .{},

		pub fn init(allocator: NeverFailingAllocator, initialCapacity: usize) Self {
			comptime std.debug.assert(@sizeOf(Self) <= 64);
			return .{
				.super = .init(allocator, initialCapacity),
			};
		}

		pub fn deinit(self: Self) void {
			self.super.deinit();
		}

		pub fn enqueue(self: *Self, elem: T) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			self.super.enqueue(elem);
		}

		pub fn dequeue(self: *Self) ?T {
			self.mutex.lock();
			defer self.mutex.unlock();
			return self.super.dequeue();
		}

		pub fn empty(self: *Self) bool {
			self.mutex.lock();
			defer self.mutex.unlock();
			return self.super.empty();
		}
	};
}

/// Allows for stack-like allocations in a fast and safe way.
/// It is safe in the sense that a regular allocator will be used when the buffer is full.
pub const StackAllocator = struct { // MARK: StackAllocator
	const AllocationTrailer = packed struct{wasFreed: bool, previousAllocationTrailer: u31};
	backingAllocator: NeverFailingAllocator,
	buffer: []align(4096) u8,
	index: usize,

	pub fn init(backingAllocator: NeverFailingAllocator, size: u31) StackAllocator {
		return .{
			.backingAllocator = backingAllocator,
			.buffer = backingAllocator.alignedAlloc(u8, 4096, size),
			.index = 0,
		};
	}

	pub fn deinit(self: StackAllocator) void {
		if(self.index != 0) {
			std.log.err("Memory leak in Stack Allocator", .{});
		}
		self.backingAllocator.free(self.buffer);
	}

	pub fn allocator(self: *StackAllocator) NeverFailingAllocator {
		return .{
			.allocator = .{
				.vtable = &.{
					.alloc = &alloc,
					.resize = &resize,
					.free = &free,
				},
				.ptr = self,
			},
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	fn isInsideBuffer(self: *StackAllocator, buf: []u8) bool {
		const bufferStart = @intFromPtr(self.buffer.ptr);
		const bufferEnd = bufferStart + self.buffer.len;
		const compare = @intFromPtr(buf.ptr);
		return compare >= bufferStart and compare < bufferEnd;
	}

	fn indexInBuffer(self: *StackAllocator, buf: []u8) usize {
		const bufferStart = @intFromPtr(self.buffer.ptr);
		const compare = @intFromPtr(buf.ptr);
		return compare - bufferStart;
	}

	fn getTrueAllocationEnd(start: usize, len: usize) usize {
		const trailerStart = std.mem.alignForward(usize, start + len, @alignOf(AllocationTrailer));
		return trailerStart + @sizeOf(AllocationTrailer);
	}

	fn getTrailerBefore(self: *StackAllocator, end: usize) *AllocationTrailer {
		const trailerStart = end - @sizeOf(AllocationTrailer);
		return @ptrCast(@alignCast(self.buffer[trailerStart..].ptr));
	}

	/// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		const start = std.mem.alignForward(usize, self.index, @as(usize, 1) << @intCast(ptr_align));
		const end = getTrueAllocationEnd(start, len);
		if(end >= self.buffer.len) return self.backingAllocator.rawAlloc(len, ptr_align, ret_addr);
		const trailer = self.getTrailerBefore(end);
		trailer.* = .{.wasFreed = false, .previousAllocationTrailer = @intCast(self.index)};
		self.index = end;
		return self.buffer.ptr + start;
	}

	/// Attempt to expand or shrink memory in place. `buf.len` must equal the
	/// length requested from the most recent successful call to `alloc` or
	/// `resize`. `buf_align` must equal the same value that was passed as the
	/// `ptr_align` parameter to the original `alloc` call.
	///
	/// A result of `true` indicates the resize was successful and the
	/// allocation now has the same address but a size of `new_len`. `false`
	/// indicates the resize could not be completed without moving the
	/// allocation to a different address.
	///
	/// `new_len` must be greater than zero.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		if(self.isInsideBuffer(buf)) {
			const start = self.indexInBuffer(buf);
			const end = getTrueAllocationEnd(start, buf.len);
			if(end != self.index) return false;
			const newEnd = getTrueAllocationEnd(start, new_len);
			if(newEnd >= self.buffer.len) return false;

			const trailer = self.getTrailerBefore(end);
			std.debug.assert(!trailer.wasFreed);
			const newTrailer = self.getTrailerBefore(newEnd);

			newTrailer.* = .{.wasFreed = false, .previousAllocationTrailer = trailer.previousAllocationTrailer};
			self.index = newEnd;
			return true;
		} else {
			return self.backingAllocator.rawResize(buf, buf_align, new_len, ret_addr);
		}
	}

	/// Free and invalidate a buffer.
	///
	/// `buf.len` must equal the most recent length returned by `alloc` or
	/// given to a successful `resize` call.
	///
	/// `buf_align` must equal the same value that was passed as the
	/// `ptr_align` parameter to the original `alloc` call.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		if(self.isInsideBuffer(buf)) {
			const start = self.indexInBuffer(buf);
			const end = getTrueAllocationEnd(start, buf.len);
			const trailer = self.getTrailerBefore(end);
			std.debug.assert(!trailer.wasFreed); // Double Free

			if(end == self.index) {
				self.index = trailer.previousAllocationTrailer;
				if(self.index != 0) {
					var previousTrailer = self.getTrailerBefore(trailer.previousAllocationTrailer);
					while(previousTrailer.wasFreed) {
						self.index = previousTrailer.previousAllocationTrailer;
						if(self.index == 0) break;
						previousTrailer = self.getTrailerBefore(previousTrailer.previousAllocationTrailer);
					}
				}
			} else {
				trailer.wasFreed = true;
			}
		} else {
			self.backingAllocator.rawFree(buf, buf_align, ret_addr);
		}
	}
};

/// An allocator that handles OutOfMemory situations by panicing or freeing memory(TODO), making it safe to ignore errors.
pub const ErrorHandlingAllocator = struct { // MARK: ErrorHandlingAllocator
	backingAllocator: Allocator,

	pub fn init(backingAllocator: Allocator) ErrorHandlingAllocator {
		return .{
			.backingAllocator = backingAllocator,
		};
	}

	pub fn allocator(self: *ErrorHandlingAllocator) NeverFailingAllocator {
		return .{
			.allocator = .{
				.vtable = &.{
					.alloc = &alloc,
					.resize = &resize,
					.free = &free,
				},
				.ptr = self,
			},
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	fn handleError() noreturn {
		@panic("Out Of Memory. Please download more RAM, reduce the render distance, or close some of your 100 browser tabs.");
	}

	/// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		return self.backingAllocator.rawAlloc(len, ptr_align, ret_addr) orelse handleError();
	}

	/// Attempt to expand or shrink memory in place. `buf.len` must equal the
	/// length requested from the most recent successful call to `alloc` or
	/// `resize`. `buf_align` must equal the same value that was passed as the
	/// `ptr_align` parameter to the original `alloc` call.
	///
	/// A result of `true` indicates the resize was successful and the
	/// allocation now has the same address but a size of `new_len`. `false`
	/// indicates the resize could not be completed without moving the
	/// allocation to a different address.
	///
	/// `new_len` must be greater than zero.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		return self.backingAllocator.rawResize(buf, buf_align, new_len, ret_addr);
	}

	/// Free and invalidate a buffer.
	///
	/// `buf.len` must equal the most recent length returned by `alloc` or
	/// given to a successful `resize` call.
	///
	/// `buf_align` must equal the same value that was passed as the
	/// `ptr_align` parameter to the original `alloc` call.
	///
	/// `ret_addr` is optionally provided as the first return address of the
	/// allocation call stack. If the value is `0` it means no return address
	/// has been provided.
	fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
		const self: *ErrorHandlingAllocator = @ptrCast(@alignCast(ctx));
		self.backingAllocator.rawFree(buf, buf_align, ret_addr);
	}
};

/// An allocator interface signaling that you can use 
pub const NeverFailingAllocator = struct { // MARK: NeverFailingAllocator
	allocator: Allocator,
	IAssertThatTheProvidedAllocatorCantFail: void,

	/// This function is not intended to be called except from within the
	/// implementation of an Allocator
	pub inline fn rawAlloc(self: NeverFailingAllocator, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
		return self.allocator.vtable.alloc(self.allocator.ptr, len, ptr_align, ret_addr);
	}

	/// This function is not intended to be called except from within the
	/// implementation of an Allocator
	pub inline fn rawResize(self: NeverFailingAllocator, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
		return self.allocator.vtable.resize(self.allocator.ptr, buf, log2_buf_align, new_len, ret_addr);
	}

	/// This function is not intended to be called except from within the
	/// implementation of an Allocator
	pub inline fn rawFree(self: NeverFailingAllocator, buf: []u8, log2_buf_align: u8, ret_addr: usize) void {
		return self.allocator.vtable.free(self.allocator.ptr, buf, log2_buf_align, ret_addr);
	}

	/// Returns a pointer to undefined memory.
	/// Call `destroy` with the result to free the memory.
	pub fn create(self: NeverFailingAllocator, comptime T: type) *T {
		return self.allocator.create(T) catch unreachable;
	}

	/// `ptr` should be the return value of `create`, or otherwise
	/// have the same address and alignment property.
	pub fn destroy(self: NeverFailingAllocator, ptr: anytype) void {
		return self.allocator.destroy(ptr);
	}

	/// Allocates an array of `n` items of type `T` and sets all the
	/// items to `undefined`. Depending on the Allocator
	/// implementation, it may be required to call `free` once the
	/// memory is no longer needed, to avoid a resource leak. If the
	/// `Allocator` implementation is unknown, then correct code will
	/// call `free` when done.
	///
	/// For allocating a single item, see `create`.
	pub fn alloc(self: NeverFailingAllocator, comptime T: type, n: usize) []T {
		return self.allocator.alloc(T, n) catch unreachable;
	}

	pub fn allocWithOptions(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		/// null means naturally aligned
		comptime optional_alignment: ?u29,
		comptime optional_sentinel: ?Elem,
	) AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel) {
		return self.allocator.allocWithOptions(Elem, n, optional_alignment, optional_sentinel) catch unreachable;
	}

	pub fn allocWithOptionsRetAddr(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		/// null means naturally aligned
		comptime optional_alignment: ?u29,
		comptime optional_sentinel: ?Elem,
		return_address: usize,
	) AllocWithOptionsPayload(Elem, optional_alignment, optional_sentinel) {
		return self.allocator.allocWithOptionsRetAddr(Elem, n, optional_alignment, optional_sentinel, return_address) catch unreachable;
	}

	fn AllocWithOptionsPayload(comptime Elem: type, comptime alignment: ?u29, comptime sentinel: ?Elem) type {
		if (sentinel) |s| {
			return [:s]align(alignment orelse @alignOf(Elem)) Elem;
		} else {
			return []align(alignment orelse @alignOf(Elem)) Elem;
		}
	}

	/// Allocates an array of `n + 1` items of type `T` and sets the first `n`
	/// items to `undefined` and the last item to `sentinel`. Depending on the
	/// Allocator implementation, it may be required to call `free` once the
	/// memory is no longer needed, to avoid a resource leak. If the
	/// `Allocator` implementation is unknown, then correct code will
	/// call `free` when done.
	///
	/// For allocating a single item, see `create`.
	pub fn allocSentinel(
		self: NeverFailingAllocator,
		comptime Elem: type,
		n: usize,
		comptime sentinel: Elem,
	) [:sentinel]Elem {
		return self.allocator.allocSentinel(Elem, n, sentinel) catch unreachable;
	}

	pub fn alignedAlloc(
		self: NeverFailingAllocator,
		comptime T: type,
		/// null means naturally aligned
		comptime alignment: ?u29,
		n: usize,
	) []align(alignment orelse @alignOf(T)) T {
		return self.allocator.alignedAlloc(T, alignment, n) catch unreachable;
	}

	pub inline fn allocAdvancedWithRetAddr(
		self: NeverFailingAllocator,
		comptime T: type,
		/// null means naturally aligned
		comptime alignment: ?u29,
		n: usize,
		return_address: usize,
	) []align(alignment orelse @alignOf(T)) T {
		return self.allocator.allocAdvancedWithRetAddr(T, alignment, n, return_address) catch unreachable;
	}

	/// Requests to modify the size of an allocation. It is guaranteed to not move
	/// the pointer, however the allocator implementation may refuse the resize
	/// request by returning `false`.
	pub fn resize(self: NeverFailingAllocator, old_mem: anytype, new_n: usize) bool {
		return self.allocator.resize(old_mem, new_n);
	}

	/// This function requests a new byte size for an existing allocation, which
	/// can be larger, smaller, or the same size as the old memory allocation.
	/// If `new_n` is 0, this is the same as `free` and it always succeeds.
	pub fn realloc(self: NeverFailingAllocator, old_mem: anytype, new_n: usize) t: {
		const Slice = @typeInfo(@TypeOf(old_mem)).pointer;
		break :t []align(Slice.alignment) Slice.child;
	} {
		return self.allocator.realloc(old_mem, new_n) catch unreachable;
	}

	pub fn reallocAdvanced(
		self: NeverFailingAllocator,
		old_mem: anytype,
		new_n: usize,
		return_address: usize,
	) t: {
		const Slice = @typeInfo(@TypeOf(old_mem)).pointer;
		break :t []align(Slice.alignment) Slice.child;
	} {
		return self.allocator.reallocAdvanced(old_mem, new_n, return_address) catch unreachable;
	}

	/// Free an array allocated with `alloc`. To free a single item,
	/// see `destroy`.
	pub fn free(self: NeverFailingAllocator, memory: anytype) void {
		self.allocator.free(memory);
	}

	/// Copies `m` to newly allocated memory. Caller owns the memory.
	pub fn dupe(self: NeverFailingAllocator, comptime T: type, m: []const T) []T {
		return self.allocator.dupe(T, m) catch unreachable;
	}

	/// Copies `m` to newly allocated memory, with a null-terminated element. Caller owns the memory.
	pub fn dupeZ(self: NeverFailingAllocator, comptime T: type, m: []const T) [:0]T {
		return self.allocator.dupeZ(T, m) catch unreachable;
	}
};

pub const NeverFailingArenaAllocator = struct { // MARK: NeverFailingArena
	arena: std.heap.ArenaAllocator,

	pub fn init(child_allocator: NeverFailingAllocator) NeverFailingArenaAllocator {
		return .{
			.arena = .init(child_allocator.allocator),
		};
	}

	pub fn deinit(self: NeverFailingArenaAllocator) void {
		self.arena.deinit();
	}

	pub fn allocator(self: *NeverFailingArenaAllocator) NeverFailingAllocator {
		return .{
			.allocator = self.arena.allocator(),
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	/// Resets the arena allocator and frees all allocated memory.
	///
	/// `mode` defines how the currently allocated memory is handled.
	/// See the variant documentation for `ResetMode` for the effects of each mode.
	///
	/// The function will return whether the reset operation was successful or not.
	/// If the reallocation  failed `false` is returned. The arena will still be fully
	/// functional in that case, all memory is released. Future allocations just might
	/// be slower.
	///
	/// NOTE: If `mode` is `free_all`, the function will always return `true`.
	pub fn reset(self: *NeverFailingArenaAllocator, mode: std.heap.ArenaAllocator.ResetMode) bool {
		return self.arena.reset(mode);
	}

	pub fn shrinkAndFree(self: *NeverFailingArenaAllocator) void {
		const node = self.arena.state.buffer_list.first orelse return;
		const allocBuf = @as([*]u8, @ptrCast(node))[0..node.data];
		const dataSize = std.mem.alignForward(usize, @sizeOf(std.SinglyLinkedList(usize).Node) + self.arena.state.end_index, @alignOf(std.SinglyLinkedList(usize).Node));
		if(self.arena.child_allocator.rawResize(allocBuf, std.math.log2(@alignOf(std.SinglyLinkedList(usize).Node)), dataSize, @returnAddress())) {
			node.data = dataSize;
		}
	}
};

pub const BufferFallbackAllocator = struct { // MARK: BufferFallbackAllocator
	fixedBuffer: std.heap.FixedBufferAllocator,
	fallbackAllocator: NeverFailingAllocator,

	pub fn init(buffer: []u8, fallbackAllocator: NeverFailingAllocator) BufferFallbackAllocator {
		return .{
			.fixedBuffer = .init(buffer),
			.fallbackAllocator = fallbackAllocator,
		};
	}

	pub fn allocator(self: *BufferFallbackAllocator) NeverFailingAllocator {
		return .{
			.allocator = .{
				.vtable = &.{
					.alloc = &alloc,
					.resize = &resize,
					.free = &free,
				},
				.ptr = self,
			},
			.IAssertThatTheProvidedAllocatorCantFail = {},
		};
	}

	fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ra: usize) ?[*]u8 {
		const self: *BufferFallbackAllocator = @ptrCast(@alignCast(ctx));
		return self.fixedBuffer.allocator().rawAlloc(len, log2_ptr_align, ra) orelse
			return self.fallbackAllocator.rawAlloc(len, log2_ptr_align, ra);
	}

	fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ra: usize) bool {
		const self: *BufferFallbackAllocator = @ptrCast(@alignCast(ctx));
		if (self.fixedBuffer.ownsPtr(buf.ptr)) {
			return self.fixedBuffer.allocator().rawResize(buf, log2_buf_align, new_len, ra);
		} else {
			return self.fallbackAllocator.rawResize(buf, log2_buf_align, new_len, ra);
		}
	}

	fn free(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, ra: usize) void {
		const self: *BufferFallbackAllocator = @ptrCast(@alignCast(ctx));
		if (self.fixedBuffer.ownsPtr(buf.ptr)) {
			return self.fixedBuffer.allocator().rawFree(buf, log2_buf_align, ra);
		} else {
			return self.fallbackAllocator.rawFree(buf, log2_buf_align, ra);
		}
	}
};

/// A simple binary heap.
/// Thread safe and blocking.
/// Expects T to have a `biggerThan(T) bool` function
pub fn BlockingMaxHeap(comptime T: type) type { // MARK: BlockingMaxHeap
	return struct {
		const initialSize = 16;
		size: usize,
		array: []T,
		waitingThreads: std.Thread.Condition,
		waitingThreadCount: u32 = 0,
		mutex: std.Thread.Mutex,
		allocator: NeverFailingAllocator,
		closed: bool = false,

		pub fn init(allocator: NeverFailingAllocator) @This() {
			return .{
				.size = 0,
				.array = allocator.alloc(T, initialSize),
				.waitingThreads = .{},
				.mutex = .{},
				.allocator = allocator,
			};
		}

		pub fn deinit(self: *@This()) void {
			self.mutex.lock();
			self.closed = true;
			// Wait for all waiting threads to leave before cleaning memory.
			self.waitingThreads.broadcast();
			while(self.waitingThreadCount != 0) {
				self.mutex.unlock();
				std.time.sleep(1000000);
				self.mutex.lock();
			}
			self.mutex.unlock();
			self.allocator.free(self.array);
		}

		/// Moves an element from a given index down the heap, such that all children are always smaller than their parents.
		fn siftDown(self: *@This(), _i: usize) void {
			assertLocked(&self.mutex);
			var i = _i;
			while(2*i + 1 < self.size) {
				const biggest = if(2*i + 2 < self.size and self.array[2*i + 2].biggerThan(self.array[2*i + 1])) 2*i + 2 else 2*i + 1;
				// Break if all childs are smaller.
				if(self.array[i].biggerThan(self.array[biggest])) return;
				// Swap it:
				const local = self.array[biggest];
				self.array[biggest] = self.array[i];
				self.array[i] = local;
				// goto the next node:
				i = biggest;
			}
		}

		/// Moves an element from a given index up the heap, such that all children are always smaller than their parents.
		fn siftUp(self: *@This(), _i: usize) void {
			assertLocked(&self.mutex);
			var i = _i;
			while(i > 0) {
				const parentIndex = (i - 1)/2;
				if(!self.array[i].biggerThan(self.array[parentIndex])) break;
				const local = self.array[parentIndex];
				self.array[parentIndex] = self.array[i];
				self.array[i] = local;
				i = parentIndex;
			}
		}

		/// Needs to be called after updating the priority of all elements.
		pub fn updatePriority(self: *@This()) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			for(0..self.size) |i| {
				self.siftUp(i);
			}
		}

		/// Returns the i-th element in the heap. Useless for most applications.
		pub fn get(self: *@This(), i: usize) ?T {
			assertLocked(&self.mutex);
			if(i >= self.size) return null;
			return self.array[i];
		}

		/// Adds a new element to the heap.
		pub fn add(self: *@This(), elem: T) void {
			self.mutex.lock();
			defer self.mutex.unlock();

			if(self.size == self.array.len) {
				self.increaseCapacity(self.size*2);
			}
			self.array[self.size] = elem;
			self.siftUp(self.size);
			self.size += 1;

			self.waitingThreads.signal();
		}

		pub fn addMany(self: *@This(), elems: []const T) void {
			self.mutex.lock();
			defer self.mutex.unlock();

			if(self.size + elems.len > self.array.len) {
				self.increaseCapacity(self.size*2 + elems.len);
			}
			for(elems) |elem| {
				self.array[self.size] = elem;
				self.siftUp(self.size);
				self.size += 1;
			}

			self.waitingThreads.signal();
		}

		fn removeIndex(self: *@This(), i: usize) void {
			assertLocked(&self.mutex);
			self.size -= 1;
			self.array[i] = self.array[self.size];
			self.siftDown(i);
		}

		/// Returns the biggest element and removes it from the heap.
		/// If empty blocks until a new object is added or the datastructure is closed.
		pub fn extractMax(self: *@This()) !T {
			self.mutex.lock();
			defer self.mutex.unlock();

			while(true) {
				if(self.size == 0) {
					self.waitingThreadCount += 1;
					self.waitingThreads.wait(&self.mutex);
					self.waitingThreadCount -= 1;
				} else {
					const ret = self.array[0];
					self.removeIndex(0);
					return ret;
				}
				if(self.closed) {
					return error.Closed;
				}
			}
		}


		fn extractAny(self: *@This()) ?T {
			self.mutex.lock();
			defer self.mutex.unlock();
			if(self.size == 0) return null;
			self.size -= 1;
			return self.array[self.size];
		}

		fn increaseCapacity(self: *@This(), newCapacity: usize) void {
			self.array = self.allocator.realloc(self.array, newCapacity);
		}
	};
}

pub const ThreadPool = struct { // MARK: ThreadPool
	pub const TaskType = enum(usize) {
		chunkgen,
		meshgenAndLighting,
		misc,
	};
	pub const taskTypes = std.enums.directEnumArrayLen(TaskType, 0);
	const Task = struct {
		cachedPriority: f32,
		self: *anyopaque,
		vtable: *const VTable,

		fn biggerThan(self: Task, other: Task) bool {
			return self.cachedPriority > other.cachedPriority;
		}
	};
	pub const VTable = struct {
		getPriority: *const fn(*anyopaque) f32,
		isStillNeeded: *const fn(*anyopaque) bool,
		run: *const fn(*anyopaque) void,
		clean: *const fn(*anyopaque) void,
		taskType: TaskType = .misc,
	};
	pub const Performance = struct {
		mutex: std.Thread.Mutex = .{},
		tasks: [taskTypes]u32 = undefined,
		utime: [taskTypes]i64 = undefined,

		fn add(self: *Performance, task: TaskType, time: i64) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			const i = @intFromEnum(task);
			self.tasks[i] += 1;
			self.utime[i] += time;
		}

		pub fn clear(self: *Performance) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			for(0..taskTypes) |i| {
				self.tasks[i] = 0;
				self.utime[i] = 0;
			}
		}

		pub fn read(self: *Performance) Performance {
			self.mutex.lock();
			defer self.mutex.unlock();
			return self.*;
		}
	};
	const refreshTime: u32 = 100; // The time after which all priorities get refreshed in milliseconds.

	threads: []std.Thread,
	currentTasks: []Atomic(?*const VTable),
	loadList: BlockingMaxHeap(Task),
	allocator: NeverFailingAllocator,

	performance: Performance,

	trueQueueSize: Atomic(usize) = .init(0),

	pub fn init(allocator: NeverFailingAllocator, threadCount: usize) *ThreadPool {
		const self = allocator.create(ThreadPool);
		self.* = .{
			.threads = allocator.alloc(std.Thread, threadCount),
			.currentTasks = allocator.alloc(Atomic(?*const VTable), threadCount),
			.loadList = BlockingMaxHeap(Task).init(allocator),
			.performance = .{},
			.allocator = allocator,
		};
		self.performance.clear();
		for(self.threads, 0..) |*thread, i| {
			thread.* = std.Thread.spawn(.{}, run, .{self, i}) catch |err| {
				std.log.err("Could not spawn Thread due to {s}", .{@errorName(err)});
				@panic("ThreadPool Creation Failed.");
			};
			var buf: [std.Thread.max_name_len]u8 = undefined;
			thread.setName(std.fmt.bufPrint(&buf, "Worker {}", .{i+1}) catch "Worker n") catch |err| std.log.err("Couldn't rename thread: {s}", .{@errorName(err)});
		}
		return self;
	}

	pub fn deinit(self: *ThreadPool) void {
		// Clear the remaining tasks:
		self.loadList.mutex.lock();
		for(self.loadList.array[0..self.loadList.size]) |task| {
			task.vtable.clean(task.self);
		}
		self.loadList.mutex.unlock();

		self.loadList.deinit();
		for(self.threads) |thread| {
			thread.join();
		}
		self.allocator.free(self.currentTasks);
		self.allocator.free(self.threads);
		self.allocator.destroy(self);
	}

	pub fn closeAllTasksOfType(self: *ThreadPool, vtable: *const VTable) void {
		self.loadList.mutex.lock();
		defer self.loadList.mutex.unlock();
		var i: u32 = 0;
		while(i < self.loadList.size) {
			const task = &self.loadList.array[i];
			if(task.vtable == vtable) {
				task.vtable.clean(task.self);
				self.loadList.removeIndex(i);
			} else {
				i += 1;
			}
		}
		// Wait for active tasks:
		for(self.currentTasks) |*task| {
			while(task.load(.monotonic) == vtable) {
				std.time.sleep(1e6);
			}
		}
	}

	fn run(self: *ThreadPool, id: usize) void {
		// In case any of the tasks wants to allocate memory:
		var sta = StackAllocator.init(main.globalAllocator, 1 << 23);
		defer sta.deinit();
		main.stackAllocator = sta.allocator();

		var lastUpdate = std.time.milliTimestamp();
		while(true) {
			{
				const task = self.loadList.extractMax() catch break;
				self.currentTasks[id].store(task.vtable, .monotonic);
				const start = std.time.microTimestamp();
				task.vtable.run(task.self);
				const end = std.time.microTimestamp();
				self.performance.add(task.vtable.taskType, end - start);
				self.currentTasks[id].store(null, .monotonic);
				_ = self.trueQueueSize.fetchSub(1, .monotonic);
			}

			if(id == 0 and std.time.milliTimestamp() -% lastUpdate > refreshTime) {
				var temporaryTaskList = main.List(Task).init(main.stackAllocator);
				defer temporaryTaskList.deinit();
				while(self.loadList.extractAny()) |task| {
					if(!task.vtable.isStillNeeded(task.self)) {
						task.vtable.clean(task.self);
						_ = self.trueQueueSize.fetchSub(1, .monotonic);
					} else {
						const taskPtr = temporaryTaskList.addOne();
						taskPtr.* = task;
						taskPtr.cachedPriority = task.vtable.getPriority(task.self);
					}
				}
				self.loadList.addMany(temporaryTaskList.items);
				lastUpdate = std.time.milliTimestamp();
			}
		}
	}

	pub fn addTask(self: *ThreadPool, task: *anyopaque, vtable: *const VTable) void {
		self.loadList.add(Task {
			.cachedPriority = vtable.getPriority(task),
			.vtable = vtable,
			.self = task,
		});
		_ = self.trueQueueSize.fetchAdd(1, .monotonic);
	}

	pub fn clear(self: *ThreadPool) void {
		// Clear the remaining tasks:
		self.loadList.mutex.lock();
		for(self.loadList.array[0..self.loadList.size]) |task| {
			task.vtable.clean(task.self);
		}
		self.loadList.size = 0;
		self.loadList.mutex.unlock();
		// Wait for the in-progress tasks to finish:
		while(true) {
			if(self.loadList.mutex.tryLock()) {
				defer self.loadList.mutex.unlock();
				if(self.loadList.waitingThreadCount == self.threads.len) {
					break;
				}
			}
			std.time.sleep(1000000);
		}
	}

	pub fn queueSize(self: *const ThreadPool) usize {
		return self.trueQueueSize.load(.monotonic);
	}
};

/// An packed array of integers with dynamic bit size.
/// The bit size can be changed using the `resize` function.
pub fn DynamicPackedIntArray(size: comptime_int) type { // MARK: DynamicPackedIntArray
	return struct {
		data: []u8 = &.{},
		bitSize: u5 = 0,

		const Self = @This();

		pub fn initCapacity(allocator: main.utils.NeverFailingAllocator, bitSize: u5) Self {
			return .{
				.data = allocator.alloc(u8, @as(usize, @divFloor(size + 7, 8))*bitSize + @sizeOf(u32)),
				.bitSize = bitSize,
			};
		}

		pub fn deinit(self: *Self, allocator: main.utils.NeverFailingAllocator) void {
			allocator.free(self.data);
			self.* = .{};
		}

		pub fn resize(self: *Self, allocator: main.utils.NeverFailingAllocator, newBitSize: u5) void {
			if(newBitSize == self.bitSize) return;
			var newSelf = Self.initCapacity(allocator, newBitSize);

			for(0..size) |i| {
				newSelf.setValue(i, self.getValue(i));
			}
			allocator.free(self.data);
			self.* = newSelf;
		}

		pub fn getValue(self: *const Self, i: usize) u32 {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return 0;
			const bitIndex = i*self.bitSize;
			const byteIndex = bitIndex >> 3;
			const bitOffset: u5 = @intCast(bitIndex & 7);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			const ptr: *align(1) u32 = @ptrCast(&self.data[byteIndex]);
			return ptr.* >> bitOffset  &  bitMask;
		}

		pub fn setValue(self: *Self, i: usize, value: u32) void {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return;
			const bitIndex = i*self.bitSize;
			const byteIndex = bitIndex >> 3;
			const bitOffset: u5 = @intCast(bitIndex & 7);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			std.debug.assert(value <= bitMask);
			const ptr: *align(1) u32 = @ptrCast(&self.data[byteIndex]);
			ptr.* &= ~(bitMask << bitOffset);
			ptr.* |= value << bitOffset;
		}

		pub fn setAndGetValue(self: *Self, i: usize, value: u32) u32 {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return 0;
			const bitIndex = i*self.bitSize;
			const byteIndex = bitIndex >> 3;
			const bitOffset: u5 = @intCast(bitIndex & 7);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			std.debug.assert(value <= bitMask);
			const ptr: *align(1) u32 = @ptrCast(&self.data[byteIndex]);
			const result = ptr.* >> bitOffset  &  bitMask;
			ptr.* &= ~(bitMask << bitOffset);
			ptr.* |= value << bitOffset;
			return result;
		}
	};
}

pub fn PaletteCompressedRegion(T: type, size: comptime_int) type { // MARK: PaletteCompressedRegion
	return struct {
		data: DynamicPackedIntArray(size) = .{},
		palette: []T,
		paletteOccupancy: []u32,
		paletteLength: u32,
		activePaletteEntries: u32,

		const Self = @This();

		pub fn init(self: *Self) void {
			self.* = .{
				.palette = main.globalAllocator.alloc(T, 1),
				.paletteOccupancy = main.globalAllocator.alloc(u32, 1),
				.paletteLength = 1,
				.activePaletteEntries = 1,
			};
			self.palette[0] = std.mem.zeroes(T);
			self.paletteOccupancy[0] = size;
		}

		pub fn initCopy(self: *Self, template: *const Self) void {
			self.* = .{
				.data = .{
					.data = main.globalAllocator.dupe(u8, template.data.data),
					.bitSize = template.data.bitSize,
				},
				.palette = main.globalAllocator.dupe(T, template.palette),
				.paletteOccupancy = main.globalAllocator.dupe(u32, template.paletteOccupancy),
				.paletteLength = template.paletteLength,
				.activePaletteEntries = template.activePaletteEntries,
			};
		}

		pub fn initCapacity(self: *Self, paletteLength: u32) void {
			std.debug.assert(paletteLength < 0x80000000 and paletteLength > 0);
			const bitSize: u5 = @intCast(std.math.log2_int_ceil(u32, paletteLength));
			const bufferLength = @as(u32, 1) << bitSize;
			self.* = .{
				.data = DynamicPackedIntArray(size).initCapacity(main.globalAllocator, bitSize),
				.palette = main.globalAllocator.alloc(T, bufferLength),
				.paletteOccupancy = main.globalAllocator.alloc(u32, bufferLength),
				.paletteLength = paletteLength,
				.activePaletteEntries = 1,
			};
			self.palette[0] = std.mem.zeroes(T);
			self.paletteOccupancy[0] = size;
		}

		pub fn deinit(self: *Self) void {
			self.data.deinit(main.globalAllocator);
			main.globalAllocator.free(self.palette);
			main.globalAllocator.free(self.paletteOccupancy);
		}

		pub fn getValue(self: *const Self, i: usize) T {
			return self.palette[self.data.getValue(i)];
		}

		fn getOrInsertPaletteIndex(noalias self: *Self, val: T) u32 {
			std.debug.assert(self.paletteLength <= self.palette.len);
			var paletteIndex: u32 = 0;
			while(paletteIndex < self.paletteLength) : (paletteIndex += 1) { // TODO: There got to be a faster way to do this. Either using SIMD or using a cache or hashmap.
				if(std.meta.eql(self.palette[paletteIndex], val)) {
					break;
				}
			}
			if(paletteIndex == self.paletteLength) {
				if(self.paletteLength == self.palette.len) {
					self.data.resize(main.globalAllocator, self.data.bitSize + 1);
					self.palette = main.globalAllocator.realloc(self.palette, @as(usize, 1) << self.data.bitSize);
					const oldLen = self.paletteOccupancy.len;
					self.paletteOccupancy = main.globalAllocator.realloc(self.paletteOccupancy, @as(usize, 1) << self.data.bitSize);
					@memset(self.paletteOccupancy[oldLen..], 0);
				}
				self.palette[paletteIndex] = val;
				self.paletteLength += 1;
				std.debug.assert(self.paletteLength <= self.palette.len);
			}
			return paletteIndex;
		}

		pub fn setRawValue(noalias self: *Self, i: usize, paletteIndex: u32) void {
			const previousPaletteIndex = self.data.setAndGetValue(i, paletteIndex);
			if(previousPaletteIndex != paletteIndex) {
				if(self.paletteOccupancy[paletteIndex] == 0) {
					self.activePaletteEntries += 1;
				}
				self.paletteOccupancy[paletteIndex] += 1;
				self.paletteOccupancy[previousPaletteIndex] -= 1;
				if(self.paletteOccupancy[previousPaletteIndex] == 0) {
					self.activePaletteEntries -= 1;
				}
			}
		}

		pub fn setValue(noalias self: *Self, i: usize, val: T) void {
			const paletteIndex = self.getOrInsertPaletteIndex(val);
			const previousPaletteIndex = self.data.setAndGetValue(i, paletteIndex);
			if(previousPaletteIndex != paletteIndex) {
				if(self.paletteOccupancy[paletteIndex] == 0) {
					self.activePaletteEntries += 1;
				}
				self.paletteOccupancy[paletteIndex] += 1;
				self.paletteOccupancy[previousPaletteIndex] -= 1;
				if(self.paletteOccupancy[previousPaletteIndex] == 0) {
					self.activePaletteEntries -= 1;
				}
			}
		}

		pub fn setValueInColumn(noalias self: *Self, startIndex: usize, endIndex: usize, val: T) void {
			std.debug.assert(startIndex < endIndex);
			const paletteIndex = self.getOrInsertPaletteIndex(val);
			for(startIndex..endIndex) |i| {
				const previousPaletteIndex = self.data.setAndGetValue(i, paletteIndex);
				self.paletteOccupancy[previousPaletteIndex] -= 1;
				if(self.paletteOccupancy[previousPaletteIndex] == 0) {
					self.activePaletteEntries -= 1;
				}
			}
			if(self.paletteOccupancy[paletteIndex] == 0) {
				self.activePaletteEntries += 1;
			}
			self.paletteOccupancy[paletteIndex] += @intCast(endIndex - startIndex);
		}

		pub fn optimizeLayout(self: *Self) void {
			if(std.math.log2_int_ceil(usize, self.palette.len) == std.math.log2_int_ceil(usize, self.activePaletteEntries)) return;

			var newData = main.utils.DynamicPackedIntArray(size).initCapacity(main.globalAllocator, @intCast(std.math.log2_int_ceil(u32, self.activePaletteEntries)));
			const paletteMap: []u32 = main.stackAllocator.alloc(u32, self.paletteLength);
			defer main.stackAllocator.free(paletteMap);
			{
				var i: u32 = 0;
				var len: u32 = self.paletteLength;
				while(i < len) : (i += 1) outer: {
					paletteMap[i] = i;
					if(self.paletteOccupancy[i] == 0) {
						while(true) {
							len -= 1;
							if(self.paletteOccupancy[len] != 0) break;
							if(len == i) break :outer;
						}
						paletteMap[len] = i;
						self.palette[i] = self.palette[len];
						self.paletteOccupancy[i] = self.paletteOccupancy[len];
						self.paletteOccupancy[len] = 0;
					}
				}
			}
			for(0..size) |i| {
				newData.setValue(i, paletteMap[self.data.getValue(i)]);
			}
			self.data.deinit(main.globalAllocator);
			self.data = newData;
			self.paletteLength = self.activePaletteEntries;
			self.palette = main.globalAllocator.realloc(self.palette, @as(usize, 1) << self.data.bitSize);
			self.paletteOccupancy = main.globalAllocator.realloc(self.paletteOccupancy, @as(usize, 1) << self.data.bitSize);
		}
	};
}

/// Implements a simple set associative cache with LRU replacement strategy.
pub fn Cache(comptime T: type, comptime numberOfBuckets: u32, comptime bucketSize: u32, comptime deinitFunction: fn(*T) void) type { // MARK: Cache
	const hashMask = numberOfBuckets-1;
	if(numberOfBuckets & hashMask != 0) @compileError("The number of buckets should be a power of 2!");

	const Bucket = struct {
		mutex: std.Thread.Mutex = .{},
		items: [bucketSize]?*T = [_]?*T {null} ** bucketSize,

		fn find(self: *@This(), compare: anytype) ?*T {
			assertLocked(&self.mutex);
			for(self.items, 0..) |item, i| {
				if(compare.equals(item)) {
					if(i != 0) {
						std.mem.copyBackwards(?*T, self.items[1..], self.items[0..i]);
						self.items[0] = item;
					}
					return item;
				}
			}
			return null;
		}

		/// Returns the object that got kicked out of the cache. This must be deinited by the user.
		fn add(self: *@This(), item: *T) ?*T {
			assertLocked(&self.mutex);
			const previous = self.items[bucketSize - 1];
			std.mem.copyBackwards(?*T, self.items[1..], self.items[0..bucketSize - 1]);
			self.items[0] = item;
			return previous;
		}

		fn findOrCreate(self: *@This(), compare: anytype, comptime initFunction: fn(@TypeOf(compare)) *T) *T {
			assertLocked(&self.mutex);
			if(self.find(compare)) |item| {
				return item;
			}
			const new = initFunction(compare);
			if(self.add(new)) |toRemove| {
				deinitFunction(toRemove);
			}
			return new;
		}

		fn clear(self: *@This()) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			for(&self.items) |*nullItem| {
				if(nullItem.*) |item| {
					deinitFunction(item);
					nullItem.* = null;
				}
			}
		}

		fn foreach(self: @This(), comptime function: fn(*T) void) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			for(self.items) |*nullItem| {
				if(nullItem) |item| {
					function(item);
				}
			}
		}
	};

	return struct {
		buckets: [numberOfBuckets]Bucket = [_]Bucket {Bucket{}} ** numberOfBuckets,
		cacheRequests: Atomic(usize) = .init(0),
		cacheMisses: Atomic(usize) = .init(0),

		///  Tries to find the entry that fits to the supplied hashable.
		pub fn find(self: *@This(), compareAndHash: anytype, comptime postGetFunction: ?fn(*T) void) ?*T {
			const index: u32 = compareAndHash.hashCode() & hashMask;
			_ = @atomicRmw(usize, &self.cacheRequests.raw, .Add, 1, .monotonic);
			self.buckets[index].mutex.lock();
			defer self.buckets[index].mutex.unlock();
			if(self.buckets[index].find(compareAndHash)) |item| {
				if(postGetFunction) |fun| fun(item);
				return item;
			}
			_ = @atomicRmw(usize, &self.cacheMisses.raw, .Add, 1, .monotonic);
			return null;
		}

		/// Clears all elements calling the deinitFunction for each element.
		pub fn clear(self: *@This()) void {
			for(&self.buckets) |*bucket| {
				bucket.clear();
			}
		}

		pub fn foreach(self: *@This(), comptime function: fn(*T) void) void {
			for(&self.buckets) |*bucket| {
				bucket.foreach(function);
			}
		}

		/// Returns the object that got kicked out of the cache. This must be deinited by the user.
		pub fn addToCache(self: *@This(), item: *T, hash: u32) ?*T {
			const index = hash & hashMask;
			self.buckets[index].mutex.lock();
			defer self.buckets[index].mutex.unlock();
			return self.buckets[index].add(item);
		}

		pub fn findOrCreate(self: *@This(), compareAndHash: anytype, comptime initFunction: fn(@TypeOf(compareAndHash)) *T, comptime postGetFunction: ?fn(*T) void) *T {
			const index: u32 = compareAndHash.hashCode() & hashMask;
			self.buckets[index].mutex.lock();
			defer self.buckets[index].mutex.unlock();
			const result = self.buckets[index].findOrCreate(compareAndHash, initFunction);
			if(postGetFunction) |fun| fun(result);
			return result;
		}
	};
}

///  https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Unit_interval_(0,_1)
pub fn unitIntervalSpline(comptime Float: type, p0: Float, m0: Float, p1: Float, m1: Float) [4]Float { // MARK: unitIntervalSpline()
	return .{
		p0,
		m0,
		-3*p0 - 2*m0 + 3*p1 - m1,
		2*p0 + m0 - 2*p1 + m1,
	};
}

pub fn GenericInterpolation(comptime elements: comptime_int) type { // MARK: GenericInterpolation
	const frames: u32 = 8;
	return struct {
		lastPos: [frames][elements]f64,
		lastVel: [frames][elements]f64,
		lastTimes: [frames]i16,
		frontIndex: u32,
		currentPoint: ?u31,
		outPos: *[elements]f64,
		outVel: *[elements]f64,

		pub fn init(self: *@This(), initialPosition: *[elements]f64, initialVelocity: *[elements]f64) void {
			self.outPos = initialPosition;
			self.outVel = initialVelocity;
			@memset(&self.lastPos, self.outPos.*);
			@memset(&self.lastVel, self.outVel.*);
			self.frontIndex = 0;
			self.currentPoint = null;
		}

		pub fn updatePosition(self: *@This(), pos: *const [elements]f64, vel: *const [elements]f64, time: i16) void {
			self.frontIndex = (self.frontIndex + 1)%frames;
			@memcpy(&self.lastPos[self.frontIndex], pos);
			@memcpy(&self.lastVel[self.frontIndex], vel);
			self.lastTimes[self.frontIndex] = time;
		}

		fn evaluateSplineAt(_t: f64, tScale: f64, p0: f64, _m0: f64, p1: f64, _m1: f64) [2]f64 {
			//  https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Unit_interval_(0,_1)
			const t = _t/tScale;
			const m0 = _m0*tScale;
			const m1 = _m1*tScale;
			const t2 = t*t;
			const t3 = t2*t;
			const a = unitIntervalSpline(f64, p0, m0, p1, m1);
			return [_]f64 {
				a[0] + a[1]*t + a[2]*t2 + a[3]*t3, // value
				(a[1] + 2*a[2]*t + 3*a[3]*t2)/tScale, // first derivative
			};
		}

		fn interpolateCoordinate(self: *@This(), i: usize, t: f64, tScale: f64) void {
			if(self.outVel[i] == 0 and self.lastVel[self.currentPoint.?][i] == 0) {
				self.outPos[i] += (self.lastPos[self.currentPoint.?][i] - self.outPos[i])*t/tScale;
			} else {
				// Use cubic interpolation to interpolate the velocity as well.
				const newValue = evaluateSplineAt(t, tScale, self.outPos[i], self.outVel[i], self.lastPos[self.currentPoint.?][i], self.lastVel[self.currentPoint.?][i]);
				self.outPos[i] = newValue[0];
				self.outVel[i] = newValue[1];
			}
		}

		fn determineNextDataPoint(self: *@This(), time: i16, lastTime: *i16) void {
			if(self.currentPoint != null and self.lastTimes[self.currentPoint.?] -% time <= 0) {
				// Jump to the last used value and adjust the time to start at that point.
				lastTime.* = self.lastTimes[self.currentPoint.?];
				@memcpy(self.outPos, &self.lastPos[self.currentPoint.?]);
				@memcpy(self.outVel, &self.lastVel[self.currentPoint.?]);
				self.currentPoint = null;
			}

			if(self.currentPoint == null) {
				// Need a new point:
				var smallestTime: i16 = std.math.maxInt(i16);
				var smallestIndex: ?u31 = null;
				for(self.lastTimes, 0..) |lastTimeI, i| {
					//                   ↓ Only using a future time value that is far enough away to prevent jumping.
					if(lastTimeI -% time >= 50 and lastTimeI -% time < smallestTime) {
						smallestTime = lastTimeI -% time;
						smallestIndex = @intCast(i);
					}
				}
				self.currentPoint = smallestIndex;
			}
		}

		pub fn update(self: *@This(), time: i16, _lastTime: i16) void {
			var lastTime = _lastTime;
			self.determineNextDataPoint(time, &lastTime);

			var deltaTime = @as(f64, @floatFromInt(time -% lastTime))/1000;
			if(deltaTime < 0) {
				std.log.err("Experienced time travel. Current time: {} Last time: {}", .{time, lastTime});
				lastTime = time;
				deltaTime = 0;
			}

			if(self.currentPoint == null) {
				const drag = std.math.pow(f64, 0.5, deltaTime);
				for(self.outPos, self.outVel) |*pos, *vel| {
					// Just move on with the current velocity.
					pos.* += (vel.*)*deltaTime;
					// Add some drag to prevent moving far away on short connection loss.
					vel.* *= drag;
				}
			} else {
				const tScale = @as(f64, @floatFromInt(self.lastTimes[self.currentPoint.?] -% lastTime))/1000;
				const t = deltaTime;
				for(self.outPos, 0..) |_, i| {
					self.interpolateCoordinate(i, t, tScale);
				}
			}
		}

		pub fn updateIndexed(self: *@This(), time: i16, _lastTime: i16, indices: []u16, comptime coordinatesPerIndex: comptime_int) void {
			var lastTime = _lastTime;
			self.determineNextDataPoint(time, &lastTime);

			var deltaTime = @as(f64, @floatFromInt(time -% lastTime))/1000;
			if(deltaTime < 0) {
				std.log.err("Experienced time travel. Current time: {} Last time: {}", .{time, lastTime});
				lastTime = time;
				deltaTime = 0;
			}

			if(self.currentPoint == null) {
				const drag = std.math.pow(f64, 0.5, deltaTime);
				for(indices) |i| {
					const index = @as(usize, i)*coordinatesPerIndex;
					for(0..coordinatesPerIndex) |j| {
						// Just move on with the current velocity.
						self.outPos[index + j] += self.outVel[index + j]*deltaTime;
						// Add some drag to prevent moving far away on short connection loss.
						self.outVel[index + j] *= drag;
					}
				}
			} else {
				const tScale = @as(f64, @floatFromInt(self.lastTimes[self.currentPoint.?] -% lastTime))/1000;
				const t = deltaTime;
				for(indices) |i| {
					const index = @as(usize, i)*coordinatesPerIndex;
					for(0..coordinatesPerIndex) |j| {
						self.interpolateCoordinate(index + j, t, tScale);
					}
				}
			}
		}
	};
}

pub const TimeDifference = struct { // MARK: TimeDifference
	difference: Atomic(i16) = .init(0),
	firstValue: bool = true,

	pub fn addDataPoint(self: *TimeDifference, time: i16) void {
		const currentTime: i16 = @truncate(std.time.milliTimestamp());
		const timeDifference = currentTime -% time;
		if(self.firstValue) {
			self.difference.store(timeDifference, .monotonic);
			self.firstValue = false;
		}
		if(timeDifference -% self.difference.load(.monotonic) > 0) {
			_ = @atomicRmw(i16, &self.difference.raw, .Add, 1, .monotonic);
		} else if(timeDifference -% self.difference.load(.monotonic) < 0) {
			_ = @atomicRmw(i16, &self.difference.raw, .Add, -1, .monotonic);
		}
	}
};

pub fn assertLocked(mutex: *const std.Thread.Mutex) void { // MARK: assertLocked()
	if(builtin.mode == .Debug) {
		std.debug.assert(!@constCast(mutex).tryLock());
	}
}

pub fn assertLockedShared(lock: *const std.Thread.RwLock) void {
	if(builtin.mode == .Debug) {
		std.debug.assert(!@constCast(lock).tryLock());
	}
}

/// A read-write lock with read priority.
pub const ReadWriteLock = struct { // MARK: ReadWriteLock
	condition: std.Thread.Condition = .{},
	mutex: std.Thread.Mutex = .{},
	readers: u32 = 0,

	pub fn lockRead(self: *ReadWriteLock) void {
		self.mutex.lock();
		self.readers += 1;
		self.mutex.unlock();
	}

	pub fn unlockRead(self: *ReadWriteLock) void {
		self.mutex.lock();
		self.readers -= 1;
		if(self.readers == 0) {
			self.condition.broadcast();
		}
		self.mutex.unlock();
	}

	pub fn lockWrite(self: *ReadWriteLock) void {
		self.mutex.lock();
		while(self.readers != 0) {
			self.condition.wait(&self.mutex);
		}
	}

	pub fn unlockWrite(self: *ReadWriteLock) void {
		self.mutex.unlock();
	}

	pub fn assertLockedWrite(self: *ReadWriteLock) void {
		if(builtin.mode == .Debug) {
			std.debug.assert(!self.mutex.tryLock());
		}
	}

	pub fn assertLockedRead(self: *ReadWriteLock) void {
		if(builtin.mode == .Debug and !builtin.sanitize_thread) {
			if(self.readers == 0) {
				std.debug.assert(!self.mutex.tryLock());
			}
		}
	}
};

pub const Side = enum {
	client,
	server,
};
