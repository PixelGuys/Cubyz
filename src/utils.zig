const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Value;
const builtin = @import("builtin");

const main = @import("main");
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

pub const file_monitor = @import("utils/file_monitor.zig");
pub const VirtualList = @import("utils/virtual_mem.zig").VirtualList;

pub const Compression = struct { // MARK: Compression
	pub fn deflate(allocator: NeverFailingAllocator, data: []const u8, level: std.compress.flate.deflate.Level) []u8 {
		var result = main.List(u8).init(allocator);
		var comp = std.compress.flate.compressor(result.writer(), .{.level = level}) catch unreachable;
		_ = comp.write(data) catch unreachable;
		comp.finish() catch unreachable;
		return result.toOwnedSlice();
	}

	pub fn inflateTo(buf: []u8, data: []const u8) !usize {
		var streamIn = std.Io.fixedBufferStream(data);
		var decomp = std.compress.flate.decompressor(streamIn.reader());
		var streamOut = std.Io.fixedBufferStream(buf);
		try decomp.decompress(streamOut.writer());
		return streamOut.getWritten().len;
	}

	pub fn pack(sourceDir: main.files.Dir, writer: anytype) !void {
		var comp = try std.compress.flate.compressor(writer, .{});
		var walker = sourceDir.walk(main.stackAllocator);
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
				std.mem.writeInt(u32, &len, @as(u32, @intCast(relPath.len)), endian);
				_ = try comp.write(&len);
				_ = try comp.write(relPath);

				const fileData = try sourceDir.read(main.stackAllocator, relPath);
				defer main.stackAllocator.free(fileData);

				std.mem.writeInt(u32, &len, @as(u32, @intCast(fileData.len)), endian);
				_ = try comp.write(&len);
				_ = try comp.write(fileData);
			}
		}
		try comp.finish();
	}

	pub fn unpack(outDir: main.files.Dir, input: []const u8) !void {
		var stream = std.io.fixedBufferStream(input);
		var decomp = std.compress.flate.decompressor(stream.reader());
		const reader = decomp.reader();
		const _data = try reader.readAllAlloc(main.stackAllocator.allocator, std.math.maxInt(usize));
		defer main.stackAllocator.free(_data);
		var data = _data;
		while(data.len != 0) {
			var len = std.mem.readInt(u32, data[0..4], endian);
			data = data[4..];
			const path = data[0..len];
			data = data[len..];
			len = std.mem.readInt(u32, data[0..4], endian);
			data = data[4..];
			const fileData = data[0..len];
			data = data[len..];

			var splitter = std.mem.splitBackwardsScalar(u8, path, '/');
			_ = splitter.first();
			try outDir.makePath(splitter.rest());
			try outDir.write(path, fileData);
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
				if(currentChances[lastOverfullIndex] < desiredChance) {
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
			return self.mem[x*self.height ..][0..self.height];
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

		pub fn clone(self: Self, allocator: NeverFailingAllocator) Self {
			const new = Self.init(allocator, self.width, self.depth, self.height);
			@memcpy(new.mem, self.mem);
			return new;
		}
	};
}

pub fn FixedSizeCircularBuffer(T: type, capacity: comptime_int) type { // MARK: FixedSizeCircularBuffer
	std.debug.assert(capacity - 1 & capacity == 0 and capacity > 0);
	const mask = capacity - 1;
	return struct {
		const Self = @This();
		mem: *[capacity]T = undefined,
		startIndex: usize = 0,
		len: usize = 0,

		pub fn init(allocator: NeverFailingAllocator) Self {
			return .{
				.mem = allocator.create([capacity]T),
			};
		}

		pub fn deinit(self: Self, allocator: NeverFailingAllocator) void {
			allocator.destroy(self.mem);
		}

		pub fn peekBack(self: Self) ?T {
			if(self.len == 0) return null;
			return self.mem[self.startIndex + self.len - 1 & mask];
		}

		pub fn peekFront(self: Self) ?T {
			if(self.len == 0) return null;
			return self.mem[self.startIndex];
		}

		pub fn pushBack(self: *Self, elem: T) !void {
			if(self.len >= capacity) return error.OutOfMemory;
			self.pushBackAssumeCapacity(elem);
		}

		pub fn forcePushBack(self: *Self, elem: T) ?T {
			const result = if(self.len >= capacity) self.popFront() else null;
			self.pushBackAssumeCapacity(elem);
			return result;
		}

		pub fn pushBackAssumeCapacity(self: *Self, elem: T) void {
			self.mem[self.startIndex + self.len & mask] = elem;
			self.len += 1;
		}

		pub fn pushFront(self: *Self, elem: T) !void {
			if(self.len >= capacity) return error.OutOfMemory;
			self.pushFrontAssumeCapacity(elem);
		}

		pub fn pushFrontAssumeCapacity(self: *Self, elem: T) void {
			self.startIndex = (self.startIndex -% 1) & mask;
			self.mem[self.startIndex] = elem;
			self.len += 1;
		}

		pub fn forcePushFront(self: *Self, elem: T) ?T {
			const result = if(self.len >= capacity) self.popBack() else null;
			self.pushFrontAssumeCapacity(elem);
			return result;
		}

		pub fn pushBackSlice(self: *Self, elems: []const T) !void {
			if(elems.len + self.len > capacity) {
				return error.OutOfMemory;
			}
			const start = self.startIndex + self.len & mask;
			const end = start + elems.len;
			if(end < self.mem.len) {
				@memcpy(self.mem[start..end], elems);
			} else {
				const mid = self.mem.len - start;
				@memcpy(self.mem[start..], elems[0..mid]);
				@memcpy(self.mem[0 .. end & mask], elems[mid..]);
			}
			self.len += elems.len;
		}

		pub fn insertSliceAtOffset(self: *Self, elems: []const T, offset: usize) !void {
			if(offset + elems.len > capacity) {
				return error.OutOfMemory;
			}
			self.len = @max(self.len, offset + elems.len);
			const start = self.startIndex + offset & mask;
			const end = start + elems.len;
			if(end < self.mem.len) {
				@memcpy(self.mem[start..end], elems);
			} else {
				const mid = self.mem.len - start;
				@memcpy(self.mem[start..], elems[0..mid]);
				@memcpy(self.mem[0 .. end & mask], elems[mid..]);
			}
		}

		pub fn popBack(self: *Self) ?T {
			if(self.len == 0) return null;
			self.len -= 1;
			return self.mem[self.startIndex + self.len & mask];
		}

		pub fn popFront(self: *Self) ?T {
			if(self.len == 0) return null;
			const result = self.mem[self.startIndex];
			self.startIndex = (self.startIndex + 1) & mask;
			self.len -= 1;
			return result;
		}

		pub fn popSliceFront(self: *Self, out: []T) !void {
			if(out.len > self.len) return error.OutOfBounds;
			const start = self.startIndex;
			const end = start + out.len;
			if(end < self.mem.len) {
				@memcpy(out, self.mem[start..end]);
			} else {
				const mid = self.mem.len - start;
				@memcpy(out[0..mid], self.mem[start..]);
				@memcpy(out[mid..], self.mem[0 .. end & mask]);
			}
			self.startIndex = self.startIndex + out.len & mask;
			self.len -= out.len;
		}

		pub fn discardElementsFront(self: *Self, n: usize) void {
			self.len -= n;
			self.startIndex = (self.startIndex + n) & mask;
		}

		pub fn getAtOffset(self: Self, i: usize) ?T {
			if(i >= self.len) return null;
			return self.mem[(self.startIndex + i) & mask];
		}
	};
}

pub fn CircularBufferQueue(comptime T: type) type { // MARK: CircularBufferQueue
	return struct {
		const Self = @This();
		mem: []T,
		mask: usize,
		startIndex: usize,
		len: usize,
		allocator: NeverFailingAllocator,

		pub fn init(allocator: NeverFailingAllocator, initialCapacity: usize) Self {
			comptime std.debug.assert(@sizeOf(Self) <= 64);
			std.debug.assert(initialCapacity - 1 & initialCapacity == 0 and initialCapacity > 0);
			return .{
				.mem = allocator.alloc(T, initialCapacity),
				.mask = initialCapacity - 1,
				.startIndex = 0,
				.len = 0,
				.allocator = allocator,
			};
		}

		pub fn deinit(self: Self) void {
			self.allocator.free(self.mem);
		}

		pub fn reset(self: *Self) void {
			self.len = 0;
		}

		fn increaseCapacity(self: *Self) void {
			const newMem = self.allocator.alloc(T, self.mem.len*2);
			@memcpy(newMem[0..(self.mem.len - self.startIndex)], self.mem[self.startIndex..]);
			@memcpy(newMem[(self.mem.len - self.startIndex)..][0..self.startIndex], self.mem[0..self.startIndex]);
			self.startIndex = 0;
			self.allocator.free(self.mem);
			self.mem = newMem;
			self.mask = self.mem.len - 1;
		}

		pub fn pushBack(self: *Self, elem: T) void {
			if(self.len == self.mem.len) {
				self.increaseCapacity();
			}
			self.mem[self.startIndex + self.len & self.mask] = elem;
			self.len += 1;
		}

		pub fn pushBackSlice(self: *Self, elems: []const T) void {
			while(elems.len + self.len > self.mem.len) {
				self.increaseCapacity();
			}
			const start = self.startIndex + self.len & self.mask;
			const end = start + elems.len;
			if(end < self.mem.len) {
				@memcpy(self.mem[start..end], elems);
			} else {
				const mid = self.mem.len - start;
				@memcpy(self.mem[start..], elems[0..mid]);
				@memcpy(self.mem[0 .. end & self.mask], elems[mid..]);
			}
			self.len += elems.len;
		}

		pub fn pushFront(self: *Self, elem: T) void {
			if(self.len == self.mem.len) {
				self.increaseCapacity();
			}
			self.startIndex = (self.startIndex -% 1) & self.mask;
			self.mem[self.startIndex] = elem;
			self.len += 1;
		}

		pub fn popFront(self: *Self) ?T {
			if(self.isEmpty()) return null;
			const result = self.mem[self.startIndex];
			self.startIndex = (self.startIndex + 1) & self.mask;
			self.len -= 1;
			return result;
		}

		pub fn popBack(self: *Self) ?T {
			if(self.isEmpty()) return null;
			self.len -= 1;
			return self.mem[self.startIndex + self.len & self.mask];
		}

		pub fn discardFront(self: *Self, amount: usize) !void {
			if(amount > self.len) return error.OutOfBounds;
			self.startIndex = (self.startIndex + amount) & self.mask;
			self.len -= amount;
		}

		pub fn peekFront(self: *Self) ?T {
			if(self.isEmpty()) return null;
			return self.mem[self.startIndex];
		}

		pub fn getSliceAtOffset(self: Self, offset: usize, result: []T) !void {
			if(offset + result.len > self.len) return error.OutOfBounds;
			const start = self.startIndex + offset & self.mask;
			const end = start + result.len;
			if(end < self.mem.len) {
				@memcpy(result, self.mem[start..end]);
			} else {
				const mid = self.mem.len - start;
				@memcpy(result[0..mid], self.mem[start..]);
				@memcpy(result[mid..], self.mem[0 .. end & self.mask]);
			}
		}

		pub fn getAtOffset(self: Self, offset: usize) !T {
			if(offset >= self.len) return error.OutOfBounds;
			return self.mem[(self.startIndex + offset) & self.mask];
		}

		pub fn isEmpty(self: *Self) bool {
			return self.len == 0;
		}

		pub fn reachedCapacity(self: *Self) bool {
			return self.len == self.mem.len;
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
			return .{
				.super = .init(allocator, initialCapacity),
			};
		}

		pub fn deinit(self: Self) void {
			self.super.deinit();
		}

		pub fn pushBack(self: *Self, elem: T) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			self.super.pushBack(elem);
		}

		pub fn popFront(self: *Self) ?T {
			self.mutex.lock();
			defer self.mutex.unlock();
			return self.super.popFront();
		}

		pub fn isEmpty(self: *Self) bool {
			self.mutex.lock();
			defer self.mutex.unlock();
			return self.super.isEmpty();
		}
	};
}

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
				std.Thread.sleep(1000000);
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

			self.waitingThreads.broadcast();
		}

		fn removeIndex(self: *@This(), i: usize) void {
			assertLocked(&self.mutex);
			self.size -= 1;
			self.array[i] = self.array[self.size];
			self.siftDown(i);
		}

		/// Returns the biggest element and removes it from the heap.
		/// If empty blocks until a new object is added or the datastructure is closed.
		pub fn extractMax(self: *@This()) error{Timeout, Closed}!T {
			self.mutex.lock();
			defer self.mutex.unlock();

			const startTime = std.time.nanoTimestamp();

			while(true) {
				if(self.size == 0) {
					self.waitingThreadCount += 1;
					defer self.waitingThreadCount -= 1;
					try self.waitingThreads.timedWait(&self.mutex, 10_000_000);
				} else {
					const ret = self.array[0];
					self.removeIndex(0);
					return ret;
				}
				if(self.closed) {
					return error.Closed;
				}
				if(std.time.nanoTimestamp() -% startTime > 10_000_000) return error.Timeout;
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
			thread.setName(std.fmt.bufPrint(&buf, "Worker {}", .{i + 1}) catch "Worker n") catch |err| std.log.err("Couldn't rename thread: {s}", .{@errorName(err)});
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
				std.Thread.sleep(1e6);
			}
		}
	}

	fn run(self: *ThreadPool, id: usize) void {
		main.initThreadLocals();
		defer main.deinitThreadLocals();

		var lastUpdate = std.time.milliTimestamp();
		outer: while(true) {
			main.heap.GarbageCollection.syncPoint();
			{
				const task = self.loadList.extractMax() catch |err| switch(err) {
					error.Timeout => continue :outer,
					error.Closed => break :outer,
				};
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
		self.loadList.add(Task{
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
		_ = self.trueQueueSize.fetchSub(self.loadList.size, .monotonic);
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
			std.Thread.sleep(1000000);
		}
	}

	pub fn queueSize(self: *const ThreadPool) usize {
		return self.trueQueueSize.load(.monotonic);
	}
};

var dynamicIntArrayAllocator: main.heap.PowerOfTwoPoolAllocator(main.chunk.chunkVolume/@bitSizeOf(u8), main.chunk.chunkVolume*@sizeOf(u16), 64) = undefined;

pub fn initDynamicIntArrayStorage() void {
	dynamicIntArrayAllocator = .init(main.globalAllocator);
}

pub fn deinitDynamicIntArrayStorage() void {
	dynamicIntArrayAllocator.deinit();
}

/// An packed array of integers with dynamic bit size.
/// The bit size can be changed using the `resize` function.
pub fn DynamicPackedIntArray(size: comptime_int) type { // MARK: DynamicPackedIntArray
	std.debug.assert(std.math.isPowerOfTwo(size));
	return struct {
		data: []align(64) Atomic(u32) = &.{},
		bitSize: u5 = 0,

		const Self = @This();

		pub fn initCapacity(bitSize: u5) Self {
			std.debug.assert(bitSize == 0 or bitSize & bitSize - 1 == 0); // Must be a power of 2
			return .{
				.data = dynamicIntArrayAllocator.allocator().alignedAlloc(Atomic(u32), .@"64", @as(usize, @divExact(size, @bitSizeOf(u32)))*bitSize),
				.bitSize = bitSize,
			};
		}

		fn deinit(self: *Self) void {
			dynamicIntArrayAllocator.allocator().free(self.data);
			self.* = .{};
		}

		inline fn bitInterleave(bits: comptime_int, source: u32) u32 {
			var result = source;
			if(bits <= 8) result = (result ^ (result << 8)) & 0x00ff00ff;
			if(bits <= 4) result = (result ^ (result << 4)) & 0x0f0f0f0f;
			if(bits <= 2) result = (result ^ (result << 2)) & 0x33333333;
			if(bits <= 1) result = (result ^ (result << 1)) & 0x55555555;
			return result;
		}

		pub fn resizeOnceFrom(self: *Self, other: *const Self) void {
			const newBitSize = if(other.bitSize != 0) other.bitSize*2 else 1;
			std.debug.assert(self.bitSize == newBitSize);

			switch(other.bitSize) {
				0 => @memset(self.data, .init(0)),
				inline 1, 2, 4, 8 => |bits| {
					for(0..other.data.len) |i| {
						const oldVal = other.data[i].load(.unordered);
						self.data[2*i].store(bitInterleave(bits, oldVal & 0xffff), .unordered);
						self.data[2*i + 1].store(bitInterleave(bits, oldVal >> 16), .unordered);
					}
				},
				else => unreachable,
			}
		}

		pub fn getValue(self: *const Self, i: usize) u32 {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return 0;
			const bitIndex = i*self.bitSize;
			const intIndex = bitIndex >> 5;
			const bitOffset: u5 = @intCast(bitIndex & 31);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			return self.data[intIndex].load(.unordered) >> bitOffset & bitMask;
		}

		pub fn setValue(self: *Self, i: usize, value: u32) void {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return;
			const bitIndex = i*self.bitSize;
			const intIndex = bitIndex >> 5;
			const bitOffset: u5 = @intCast(bitIndex & 31);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			std.debug.assert(value <= bitMask);
			const ptr: *Atomic(u32) = &self.data[intIndex];
			const newValue = (ptr.load(.unordered) & ~(bitMask << bitOffset)) | value << bitOffset;
			ptr.store(newValue, .unordered);
		}

		pub fn setAndGetValue(self: *Self, i: usize, value: u32) u32 {
			std.debug.assert(i < size);
			if(self.bitSize == 0) return 0;
			const bitIndex = i*self.bitSize;
			const intIndex = bitIndex >> 5;
			const bitOffset: u5 = @intCast(bitIndex & 31);
			const bitMask = (@as(u32, 1) << self.bitSize) - 1;
			std.debug.assert(value <= bitMask);
			const ptr: *Atomic(u32) = &self.data[intIndex];
			const oldValue = ptr.load(.unordered);
			const result = oldValue >> bitOffset & bitMask;
			const newValue = (oldValue & ~(bitMask << bitOffset)) | value << bitOffset;
			ptr.store(newValue, .unordered);
			return result;
		}
	};
}

pub fn PaletteCompressedRegion(T: type, size: comptime_int) type { // MARK: PaletteCompressedRegion
	const Impl = struct {
		data: DynamicPackedIntArray(size) = .{},
		palette: []Atomic(T),
		paletteOccupancy: []u32,
		paletteLength: u32,
		activePaletteEntries: u32,
	};
	return struct {
		impl: Atomic(*Impl),
		const Self = @This();

		pub fn init(self: *Self) void {
			const impl = main.globalAllocator.create(Impl);
			self.* = .{
				.impl = .init(impl),
			};
			impl.* = .{
				.palette = main.globalAllocator.alloc(Atomic(T), 1),
				.paletteOccupancy = main.globalAllocator.alloc(u32, 1),
				.paletteLength = 1,
				.activePaletteEntries = 1,
			};
			impl.palette[0] = .init(std.mem.zeroes(T));
			impl.paletteOccupancy[0] = size;
		}

		pub fn initCopy(self: *Self, template: *const Self) void {
			const impl = main.globalAllocator.create(Impl);
			const templateImpl = template.impl.load(.acquire);
			const dataDupe = DynamicPackedIntArray(size).initCapacity(templateImpl.data.bitSize);
			@memcpy(dataDupe.data, templateImpl.data.data);
			self.* = .{
				.impl = .init(impl),
			};
			impl.* = .{
				.data = dataDupe,
				.palette = main.globalAllocator.dupe(Atomic(T), templateImpl.palette),
				.paletteOccupancy = main.globalAllocator.dupe(u32, templateImpl.paletteOccupancy),
				.paletteLength = templateImpl.paletteLength,
				.activePaletteEntries = templateImpl.activePaletteEntries,
			};
		}

		pub fn initCapacity(self: *Self, paletteLength: u32) void {
			std.debug.assert(paletteLength < 0x80000000 and paletteLength > 0);
			const bitSize: u5 = getTargetBitSize(paletteLength);
			const bufferLength = @as(u32, 1) << bitSize;
			const impl = main.globalAllocator.create(Impl);
			self.* = .{
				.impl = .init(impl),
			};
			impl.* = .{
				.data = DynamicPackedIntArray(size).initCapacity(bitSize),
				.palette = main.globalAllocator.alloc(Atomic(T), bufferLength),
				.paletteOccupancy = main.globalAllocator.alloc(u32, bufferLength),
				.paletteLength = paletteLength,
				.activePaletteEntries = 1,
			};
			impl.palette[0] = .init(std.mem.zeroes(T));
			impl.paletteOccupancy[0] = size;
			@memset(impl.paletteOccupancy[1..], 0);
			@memset(impl.data.data, .init(0));
		}

		fn privateDeinit(impl: *Impl) void {
			impl.data.deinit();
			main.globalAllocator.free(impl.palette);
			main.globalAllocator.free(impl.paletteOccupancy);
			main.globalAllocator.destroy(impl);
		}

		pub fn deferredDeinit(self: *Self) void {
			main.heap.GarbageCollection.deferredFree(.{.ptr = self.impl.raw, .freeFunction = main.utils.castFunctionSelfToAnyopaque(privateDeinit)});
		}

		fn getTargetBitSize(paletteLength: u32) u5 {
			const base: u5 = @intCast(std.math.log2_int_ceil(u32, paletteLength));
			if(base == 0) return 0;
			const logLog = std.math.log2_int_ceil(u5, base);
			return @as(u5, 1) << logLog;
		}

		pub fn getValue(self: *const Self, i: usize) T {
			const impl = self.impl.load(.acquire);
			return impl.palette[impl.data.getValue(i)].load(.unordered);
		}

		pub fn palette(self: *const Self) []Atomic(T) {
			const impl = self.impl.raw;
			return impl.palette[0..impl.paletteLength];
		}

		pub fn fillUniform(self: *Self, value: T) void {
			const impl = self.impl.raw;
			if(impl.paletteLength == 1) {
				impl.palette[0].store(value, .unordered);
				return;
			}
			var newSelf: Self = undefined;
			newSelf.init();
			newSelf.impl.raw.palette[0] = .init(value);
			newSelf.impl.raw = self.impl.swap(newSelf.impl.raw, .release);
			newSelf.deferredDeinit();
		}

		fn getOrInsertPaletteIndex(noalias self: *Self, val: T) u32 {
			var impl = self.impl.raw;
			std.debug.assert(impl.paletteLength <= impl.palette.len);
			var paletteIndex: u32 = 0;
			while(paletteIndex < impl.paletteLength) : (paletteIndex += 1) {
				if(std.meta.eql(impl.palette[paletteIndex].load(.unordered), val)) {
					break;
				}
			}
			if(paletteIndex == impl.paletteLength) {
				if(impl.paletteLength == impl.palette.len) {
					var newSelf: Self = undefined;
					newSelf.initCapacity(impl.paletteLength*2);
					const newImpl = newSelf.impl.raw;
					// TODO: Resize stuff
					newImpl.data.resizeOnceFrom(&impl.data);
					@memcpy(newImpl.palette[0..impl.palette.len], impl.palette);
					@memcpy(newImpl.paletteOccupancy[0..impl.paletteOccupancy.len], impl.paletteOccupancy);
					@memset(newImpl.paletteOccupancy[impl.paletteOccupancy.len..], 0);
					newImpl.activePaletteEntries = impl.activePaletteEntries;
					newImpl.paletteLength = impl.paletteLength;
					newSelf.impl.raw = self.impl.swap(newImpl, .release);
					newSelf.deferredDeinit();
					impl = newImpl;
				}
				impl.palette[paletteIndex].store(val, .unordered);
				impl.paletteLength += 1;
				std.debug.assert(impl.paletteLength <= impl.palette.len);
			}
			return paletteIndex;
		}

		pub fn setRawValue(noalias self: *Self, i: usize, paletteIndex: u32) void {
			const impl = self.impl.raw;
			const previousPaletteIndex = impl.data.setAndGetValue(i, paletteIndex);
			if(previousPaletteIndex != paletteIndex) {
				if(impl.paletteOccupancy[paletteIndex] == 0) {
					impl.activePaletteEntries += 1;
				}
				impl.paletteOccupancy[paletteIndex] += 1;
				impl.paletteOccupancy[previousPaletteIndex] -= 1;
				if(impl.paletteOccupancy[previousPaletteIndex] == 0) {
					impl.activePaletteEntries -= 1;
				}
			}
		}

		pub fn setValue(noalias self: *Self, i: usize, val: T) void {
			const paletteIndex = self.getOrInsertPaletteIndex(val);
			const impl = self.impl.raw;
			const previousPaletteIndex = impl.data.setAndGetValue(i, paletteIndex);
			if(previousPaletteIndex != paletteIndex) {
				if(impl.paletteOccupancy[paletteIndex] == 0) {
					impl.activePaletteEntries += 1;
				}
				impl.paletteOccupancy[paletteIndex] += 1;
				impl.paletteOccupancy[previousPaletteIndex] -= 1;
				if(impl.paletteOccupancy[previousPaletteIndex] == 0) {
					impl.activePaletteEntries -= 1;
				}
			}
		}

		pub fn setValueInColumn(noalias self: *Self, startIndex: usize, endIndex: usize, val: T) void {
			std.debug.assert(startIndex < endIndex);
			const paletteIndex = self.getOrInsertPaletteIndex(val);
			const impl = self.impl.raw;
			for(startIndex..endIndex) |i| {
				const previousPaletteIndex = impl.data.setAndGetValue(i, paletteIndex);
				impl.paletteOccupancy[previousPaletteIndex] -= 1;
				if(impl.paletteOccupancy[previousPaletteIndex] == 0) {
					impl.activePaletteEntries -= 1;
				}
			}
			if(impl.paletteOccupancy[paletteIndex] == 0) {
				impl.activePaletteEntries += 1;
			}
			impl.paletteOccupancy[paletteIndex] += @intCast(endIndex - startIndex);
		}

		pub fn optimizeLayout(self: *Self) void {
			const impl = self.impl.raw;
			const newBitSize = getTargetBitSize(@intCast(impl.activePaletteEntries));
			if(impl.data.bitSize == newBitSize) return;

			var newSelf: Self = undefined;
			newSelf.initCapacity(impl.activePaletteEntries);
			const newImpl = newSelf.impl.raw;
			const paletteMap: []u32 = main.stackAllocator.alloc(u32, impl.paletteLength);
			defer main.stackAllocator.free(paletteMap);
			{
				var iNew: u32 = 0;
				var iOld: u32 = 0;
				const len: u32 = impl.paletteLength;
				while(iOld < len) : ({
					iNew += 1;
					iOld += 1;
				}) outer: {
					while(impl.paletteOccupancy[iOld] == 0) {
						iOld += 1;
						if(iOld >= len) break :outer;
					}
					if(iNew >= impl.activePaletteEntries) std.log.err("{} {}", .{iNew, impl.activePaletteEntries});
					std.debug.assert(iNew < impl.activePaletteEntries);
					std.debug.assert(iOld < impl.paletteLength);
					paletteMap[iOld] = iNew;
					newImpl.palette[iNew] = .init(impl.palette[iOld].load(.unordered));
					newImpl.paletteOccupancy[iNew] = impl.paletteOccupancy[iOld];
				}
			}
			for(0..size) |i| {
				newImpl.data.setValue(i, paletteMap[impl.data.getValue(i)]);
			}
			newImpl.paletteLength = impl.activePaletteEntries;
			newImpl.activePaletteEntries = impl.activePaletteEntries;
			newSelf.impl.raw = self.impl.swap(newSelf.impl.raw, .release);
			newSelf.deferredDeinit();
		}
	};
}

/// Implements a simple set associative cache with LRU replacement strategy.
pub fn Cache(comptime T: type, comptime numberOfBuckets: u32, comptime bucketSize: u32, comptime deinitFunction: fn(*T) void) type { // MARK: Cache
	const hashMask = numberOfBuckets - 1;
	if(numberOfBuckets & hashMask != 0) @compileError("The number of buckets should be a power of 2!");

	const Bucket = struct {
		mutex: std.Thread.Mutex = .{},
		items: [bucketSize]?*T = @splat(null),

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
			std.mem.copyBackwards(?*T, self.items[1..], self.items[0 .. bucketSize - 1]);
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
		buckets: [numberOfBuckets]Bucket = @splat(.{}),
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
			return [_]f64{
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
				std.log.warn("Experienced time travel. Current time: {} Last time: {}", .{time, lastTime});
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
				std.log.warn("Experienced time travel. Current time: {} Last time: {}", .{time, lastTime});
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

const endian: std.builtin.Endian = .big;

pub const BinaryReader = struct {
	remaining: []const u8,

	pub const AllErrors = error{OutOfBounds, IntOutOfBounds, InvalidEnumTag, InvalidFloat};

	pub fn init(data: []const u8) BinaryReader {
		return .{.remaining = data};
	}

	pub fn readVec(self: *BinaryReader, T: type) error{OutOfBounds, IntOutOfBounds, InvalidFloat}!T {
		const typeInfo = @typeInfo(T).vector;
		var result: T = undefined;
		inline for(0..typeInfo.len) |i| {
			switch(@typeInfo(typeInfo.child)) {
				.int => {
					result[i] = try self.readInt(typeInfo.child);
				},
				.float => {
					result[i] = try self.readFloat(typeInfo.child);
				},
				else => unreachable,
			}
		}
		return result;
	}

	pub fn readInt(self: *BinaryReader, T: type) error{OutOfBounds, IntOutOfBounds}!T {
		if(@mod(@typeInfo(T).int.bits, 8) != 0) {
			const fullBits = comptime std.mem.alignForward(u16, @typeInfo(T).int.bits, 8);
			const FullType = std.meta.Int(@typeInfo(T).int.signedness, fullBits);
			const val = try self.readInt(FullType);
			return std.math.cast(T, val) orelse return error.IntOutOfBounds;
		}
		const bufSize = @divExact(@typeInfo(T).int.bits, 8);
		if(self.remaining.len < bufSize) return error.OutOfBounds;
		defer self.remaining = self.remaining[bufSize..];
		return std.mem.readInt(T, self.remaining[0..bufSize], endian);
	}

	pub fn readVarInt(self: *BinaryReader, T: type) !T {
		comptime std.debug.assert(@typeInfo(T).int.signedness == .unsigned);
		comptime std.debug.assert(@bitSizeOf(T) > 8); // Why would you use a VarInt for this?
		var result: T = 0;
		var shift: std.meta.Int(.unsigned, std.math.log2_int_ceil(usize, @bitSizeOf(T))) = 0;
		while(true) {
			const nextByte = try self.readInt(u8);
			const value: T = nextByte & 0x7f;
			result |= try std.math.shlExact(T, value, shift);
			if(nextByte & 0x80 == 0) break;
			shift = try std.math.add(@TypeOf(shift), shift, 7);
		}
		return result;
	}

	pub fn readFloat(self: *BinaryReader, T: type) error{OutOfBounds, IntOutOfBounds, InvalidFloat}!T {
		const IntT = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
		const result: T = @bitCast(try self.readInt(IntT));
		if(!std.math.isFinite(result)) return error.InvalidFloat;
		return result;
	}

	pub fn readEnum(self: *BinaryReader, T: type) error{OutOfBounds, IntOutOfBounds, InvalidEnumTag}!T {
		const int = try self.readInt(@typeInfo(T).@"enum".tag_type);
		return std.meta.intToEnum(T, int);
	}

	pub fn readBool(self: *BinaryReader) error{OutOfBounds, IntOutOfBounds, InvalidEnumTag}!bool {
		const int = try self.readInt(u1);
		return int != 0;
	}

	pub fn readUntilDelimiter(self: *BinaryReader, comptime delimiter: u8) ![:delimiter]const u8 {
		const len = std.mem.indexOfScalar(u8, self.remaining, delimiter) orelse return error.OutOfBounds;
		defer self.remaining = self.remaining[len + 1 ..];
		return self.remaining[0..len :delimiter];
	}

	pub fn readSlice(self: *BinaryReader, length: usize) error{OutOfBounds, IntOutOfBounds}![]const u8 {
		if(self.remaining.len < length) return error.OutOfBounds;
		defer self.remaining = self.remaining[length..];
		return self.remaining[0..length];
	}
};

pub const BinaryWriter = struct {
	data: main.List(u8),

	pub fn init(allocator: NeverFailingAllocator) BinaryWriter {
		return .{.data = .init(allocator)};
	}

	pub fn initCapacity(allocator: NeverFailingAllocator, capacity: usize) BinaryWriter {
		return .{.data = .initCapacity(allocator, capacity)};
	}

	pub fn deinit(self: *BinaryWriter) void {
		self.data.deinit();
	}

	pub fn writeVec(self: *BinaryWriter, T: type, value: T) void {
		const typeInfo = @typeInfo(T).vector;
		inline for(0..typeInfo.len) |i| {
			switch(@typeInfo(typeInfo.child)) {
				.int => {
					self.writeInt(typeInfo.child, value[i]);
				},
				.float => {
					self.writeFloat(typeInfo.child, value[i]);
				},
				else => unreachable,
			}
		}
	}

	pub fn writeInt(self: *BinaryWriter, T: type, value: T) void {
		if(@mod(@typeInfo(T).int.bits, 8) != 0) {
			const fullBits = comptime std.mem.alignForward(u16, @typeInfo(T).int.bits, 8);
			const FullType = std.meta.Int(@typeInfo(T).int.signedness, fullBits);
			return self.writeInt(FullType, value);
		}
		const bufSize = @divExact(@typeInfo(T).int.bits, 8);
		std.mem.writeInt(T, self.data.addMany(bufSize)[0..bufSize], value, endian);
	}

	pub fn writeVarInt(self: *BinaryWriter, T: type, value: T) void {
		comptime std.debug.assert(@typeInfo(T).int.signedness == .unsigned);
		comptime std.debug.assert(@bitSizeOf(T) > 8); // Why would you use a VarInt for this?
		var remaining: T = value;
		while(true) {
			var writeByte: u8 = @intCast(remaining & 0x7f);
			remaining >>= 7;
			if(remaining != 0) writeByte |= 0x80;
			self.writeInt(u8, writeByte);
			if(remaining == 0) break;
		}
	}

	pub fn writeFloat(self: *BinaryWriter, T: type, value: T) void {
		const IntT = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
		self.writeInt(IntT, @bitCast(value));
	}

	pub fn writeEnum(self: *BinaryWriter, T: type, value: T) void {
		self.writeInt(@typeInfo(T).@"enum".tag_type, @intFromEnum(value));
	}

	pub fn writeBool(self: *BinaryWriter, value: bool) void {
		self.writeInt(u1, @intFromBool(value));
	}

	pub fn writeSlice(self: *BinaryWriter, slice: []const u8) void {
		self.data.appendSlice(slice);
	}

	pub fn writeWithDelimiter(self: *BinaryWriter, slice: []const u8, delimiter: u8) void {
		std.debug.assert(!std.mem.containsAtLeast(u8, slice, 1, &.{delimiter}));
		self.writeSlice(slice);
		self.data.append(delimiter);
	}
};

const ReadWriteTest = struct {
	fn getWriter() BinaryWriter {
		return .init(main.heap.testingAllocator);
	}
	fn getReader(data: []const u8) BinaryReader {
		return .init(data);
	}
	fn testInt(comptime IntT: type, expected: IntT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeInt(IntT, expected);

		const expectedWidth = std.math.divCeil(comptime_int, @bitSizeOf(IntT), 8);
		try std.testing.expectEqual(expectedWidth, writer.data.items.len);

		var reader = getReader(writer.data.items);
		const actual = try reader.readInt(IntT);

		try std.testing.expectEqual(expected, actual);
	}
	fn testVarInt(comptime IntT: type, expected: IntT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeVarInt(IntT, expected);

		const expectedWidth = 1 + std.math.log2_int(IntT, @max(1, expected))/7;
		try std.testing.expectEqual(expectedWidth, writer.data.items.len);

		var reader = getReader(writer.data.items);
		const actual = try reader.readVarInt(IntT);

		try std.testing.expectEqual(expected, actual);
	}
	fn testFloat(comptime FloatT: type, expected: FloatT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeFloat(FloatT, expected);

		var reader = getReader(writer.data.items);
		const actual = try reader.readFloat(FloatT);

		try std.testing.expectEqual(expected, actual);
	}
	fn testInvalidFloat(comptime FloatT: type, input: FloatT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeFloat(FloatT, input);

		var reader = getReader(writer.data.items);
		const actual = reader.readFloat(FloatT);

		try std.testing.expectError(error.InvalidFloat, actual);
	}
	fn testEnum(comptime EnumT: type, expected: EnumT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeEnum(EnumT, expected);

		var reader = getReader(writer.data.items);
		const actual = try reader.readEnum(EnumT);

		try std.testing.expectEqual(expected, actual);
	}
	fn TestEnum(comptime IntT: type) type {
		return enum(IntT) {
			first = std.math.minInt(IntT),
			center = (std.math.maxInt(IntT) + std.math.minInt(IntT))/2,
			last = std.math.maxInt(IntT),
		};
	}
	fn testVec(comptime VecT: type, expected: VecT) !void {
		var writer = getWriter();
		defer writer.deinit();
		writer.writeVec(VecT, expected);

		var reader = getReader(writer.data.items);
		const actual = try reader.readVec(VecT);

		try std.testing.expectEqual(expected, actual);
	}
};

test "read/write unsigned int" {
	inline for([_]type{u0, u1, u2, u4, u5, u8, u16, u31, u32, u64, u128}) |intT| {
		const min = std.math.minInt(intT);
		const max = std.math.maxInt(intT);
		const mid = (max + min)/2;

		try ReadWriteTest.testInt(intT, min);
		try ReadWriteTest.testInt(intT, mid);
		try ReadWriteTest.testInt(intT, max);
	}
}

test "read/write signed int" {
	inline for([_]type{i1, i2, i4, i5, i8, i16, i31, i32, i64, i128}) |intT| {
		const min = std.math.minInt(intT);
		const lowerMid = std.math.minInt(intT)/2;
		const upperMid = std.math.maxInt(intT)/2;
		const max = std.math.maxInt(intT);

		try ReadWriteTest.testInt(intT, min);
		try ReadWriteTest.testInt(intT, lowerMid);
		try ReadWriteTest.testInt(intT, 0);
		try ReadWriteTest.testInt(intT, upperMid);
		try ReadWriteTest.testInt(intT, max);
	}
}

test "read/write unsigned varint" {
	inline for([_]type{u9, u16, u31, u32, u64, u128}) |IntT| {
		for(0..@bitSizeOf(IntT)) |i| {
			try ReadWriteTest.testVarInt(IntT, @as(IntT, 1) << @intCast(i));
			try ReadWriteTest.testVarInt(IntT, (@as(IntT, 1) << @intCast(i)) - 1);
		}
		const max = std.math.maxInt(IntT);
		try ReadWriteTest.testVarInt(IntT, max);
	}
}

test "read/write float" {
	inline for([_]type{f16, f32, f64, f80, f128}) |floatT| {
		try ReadWriteTest.testFloat(floatT, std.math.floatMax(floatT));
		try ReadWriteTest.testFloat(floatT, 0.0012443);
		try ReadWriteTest.testFloat(floatT, 0.0);
		try ReadWriteTest.testFloat(floatT, 6457.0);
		try ReadWriteTest.testInvalidFloat(floatT, std.math.inf(floatT));
		try ReadWriteTest.testInvalidFloat(floatT, -std.math.inf(floatT));
		try ReadWriteTest.testInvalidFloat(floatT, std.math.nan(floatT));
		try ReadWriteTest.testFloat(floatT, std.math.floatMin(floatT));
	}
}

test "read/write enum" {
	inline for([_]type{
		ReadWriteTest.TestEnum(u2),
		ReadWriteTest.TestEnum(u4),
		ReadWriteTest.TestEnum(u5),
		ReadWriteTest.TestEnum(u8),
		ReadWriteTest.TestEnum(u16),
		ReadWriteTest.TestEnum(u32),
		ReadWriteTest.TestEnum(i2),
		ReadWriteTest.TestEnum(i4),
		ReadWriteTest.TestEnum(i5),
		ReadWriteTest.TestEnum(i8),
		ReadWriteTest.TestEnum(i16),
		ReadWriteTest.TestEnum(i32),
	}) |enumT| {
		try ReadWriteTest.testEnum(enumT, .first);
		try ReadWriteTest.testEnum(enumT, .center);
		try ReadWriteTest.testEnum(enumT, .last);
	}
}

test "read/write Vec3i" {
	try ReadWriteTest.testVec(main.vec.Vec3i, .{0, 0, 0});
	try ReadWriteTest.testVec(main.vec.Vec3i, .{
		std.math.maxInt(@typeInfo(main.vec.Vec3i).vector.child),
		std.math.minInt(@typeInfo(main.vec.Vec3i).vector.child),
		std.math.minInt(@typeInfo(main.vec.Vec3i).vector.child),
	});
	try ReadWriteTest.testVec(main.vec.Vec3i, .{
		std.math.minInt(@typeInfo(main.vec.Vec3i).vector.child),
		std.math.maxInt(@typeInfo(main.vec.Vec3i).vector.child),
		std.math.maxInt(@typeInfo(main.vec.Vec3i).vector.child),
	});
}

test "read/write Vec3f/Vec3d" {
	inline for([_]type{main.vec.Vec3f, main.vec.Vec3d}) |vecT| {
		try ReadWriteTest.testVec(vecT, .{0, 0, 0});
		try ReadWriteTest.testVec(vecT, .{0.0043, 0.01123, 0.05043});
		try ReadWriteTest.testVec(vecT, .{5345.0, 42.0, 7854.0});
		try ReadWriteTest.testVec(vecT, .{
			std.math.floatMax(@typeInfo(vecT).vector.child),
			std.math.floatMin(@typeInfo(vecT).vector.child),
			std.math.floatMin(@typeInfo(vecT).vector.child),
		});
		try ReadWriteTest.testVec(vecT, .{
			std.math.floatMin(@typeInfo(vecT).vector.child),
			std.math.floatMax(@typeInfo(vecT).vector.child),
			std.math.floatMax(@typeInfo(vecT).vector.child),
		});
	}
}

test "read/write mixed" {
	const type0 = u4;
	const expected0 = 5;

	const type1 = main.vec.Vec3i;
	const expected1 = type1{3, -10, 44};

	const type2 = enum(u3) {first, second, third};
	const expected2 = .second;

	const type3 = f32;
	const expected3 = 0.1234;

	const expected4 = "Hello World!";

	var writer = ReadWriteTest.getWriter();
	defer writer.deinit();

	writer.writeInt(type0, expected0);
	writer.writeVec(type1, expected1);
	writer.writeEnum(type2, expected2);
	writer.writeFloat(type3, expected3);
	writer.writeSlice(expected4);

	var reader = ReadWriteTest.getReader(writer.data.items);

	try std.testing.expectEqual(expected0, try reader.readInt(type0));
	try std.testing.expectEqual(expected1, try reader.readVec(type1));
	try std.testing.expectEqual(expected2, try reader.readEnum(type2));
	try std.testing.expectEqual(expected3, try reader.readFloat(type3));
	try std.testing.expectEqualStrings(expected4, try reader.readSlice(expected4.len));

	try std.testing.expect(reader.remaining.len == 0);
}

pub fn DenseId(comptime IdType: type) type {
	std.debug.assert(@typeInfo(IdType) == .int);
	std.debug.assert(@typeInfo(IdType).int.signedness == .unsigned);

	return enum(IdType) {
		noValue = std.math.maxInt(IdType),
		_,
	};
}

pub fn SparseSet(comptime T: type, comptime IdType: type) type { // MARK: SparseSet
	std.debug.assert(@intFromEnum(IdType.noValue) == std.math.maxInt(@typeInfo(IdType).@"enum".tag_type));

	return struct {
		const Self = @This();

		dense: main.ListUnmanaged(T) = .{},
		denseToSparseIndex: main.ListUnmanaged(IdType) = .{},
		sparseToDenseIndex: main.ListUnmanaged(IdType) = .{},

		pub fn clear(self: *Self) void {
			self.dense.clearRetainingCapacity();
			self.denseToSparseIndex.clearRetainingCapacity();
			self.sparseToDenseIndex.clearRetainingCapacity();
		}

		pub fn deinit(self: *Self, allocator: NeverFailingAllocator) void {
			self.dense.deinit(allocator);
			self.denseToSparseIndex.deinit(allocator);
			self.sparseToDenseIndex.deinit(allocator);
		}

		pub fn contains(self: *Self, id: IdType) bool {
			return @intFromEnum(id) < self.sparseToDenseIndex.items.len and self.sparseToDenseIndex.items[@intFromEnum(id)] != .noValue;
		}

		pub fn add(self: *Self, allocator: NeverFailingAllocator, id: IdType) *T {
			std.debug.assert(id != .noValue);

			const denseId: IdType = @enumFromInt(self.dense.items.len);

			if(@intFromEnum(id) >= self.sparseToDenseIndex.items.len) {
				self.sparseToDenseIndex.appendNTimes(allocator, .noValue, @intFromEnum(id) - self.sparseToDenseIndex.items.len + 1);
			}

			std.debug.assert(self.sparseToDenseIndex.items[@intFromEnum(id)] == .noValue);

			self.sparseToDenseIndex.items[@intFromEnum(id)] = denseId;
			self.denseToSparseIndex.append(allocator, id);
			return self.dense.addOne(allocator);
		}

		pub fn set(self: *Self, allocator: NeverFailingAllocator, id: IdType, value: T) void {
			self.add(allocator, id).* = value;
		}

		pub fn fetchRemove(self: *Self, id: IdType) !T {
			if(!self.contains(id)) return error.ElementNotFound;

			const denseId = @intFromEnum(self.sparseToDenseIndex.items[@intFromEnum(id)]);
			self.sparseToDenseIndex.items[@intFromEnum(id)] = .noValue;

			const result = self.dense.swapRemove(denseId);
			_ = self.denseToSparseIndex.swapRemove(denseId);

			if(denseId != self.dense.items.len) {
				self.sparseToDenseIndex.items[@intFromEnum(self.denseToSparseIndex.items[denseId])] = @enumFromInt(denseId);
			}
			return result;
		}

		pub fn remove(self: *Self, id: IdType) !void {
			_ = try self.fetchRemove(id);
		}

		pub fn get(self: *Self, id: IdType) ?*T {
			if(@intFromEnum(id) >= self.sparseToDenseIndex.items.len) return null;
			const index = self.sparseToDenseIndex.items[@intFromEnum(id)];
			if(index == .noValue) return null;
			return &self.dense.items[@intFromEnum(index)];
		}
	};
}

test "SparseSet/set at zero" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	const index: IdType = @enumFromInt(0);

	set.set(main.heap.testingAllocator, index, 5);
	try std.testing.expectEqual(set.get(index).?.*, 5);
}

test "SparseSet/set at 100" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	const index: IdType = @enumFromInt(100);

	set.set(main.heap.testingAllocator, index, 5);
	try std.testing.expectEqual(set.get(index).?.*, 5);
}

test "SparseSet/remove first" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	const expectSecond: u32 = 100;

	const firstId: IdType = @enumFromInt(0);
	const secondId: IdType = @enumFromInt(1);

	set.set(main.heap.testingAllocator, firstId, 5);
	set.set(main.heap.testingAllocator, secondId, expectSecond);

	try set.remove(firstId);

	try std.testing.expectEqual(set.get(secondId).?.*, expectSecond);
}

test "SparseSet/remove last" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	set.set(main.heap.testingAllocator, @enumFromInt(0), 5);

	try set.remove(@enumFromInt(0));
}

test "SparseSet/remove entry that doesn't exist" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	try std.testing.expectError(error.ElementNotFound, set.remove(@enumFromInt(0)));
}

test "SparseSet/remove entry twice" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	set.set(main.heap.testingAllocator, @enumFromInt(0), 5);

	try set.remove(@enumFromInt(0));
	try std.testing.expectError(error.ElementNotFound, set.remove(@enumFromInt(0)));
}

test "SparseSet/reusing" {
	const IdType = DenseId(u32);
	var set: SparseSet(u32, IdType) = .{};
	defer set.deinit(main.heap.testingAllocator);

	const expectSecond = 100;
	const expectNew = 10;

	const firstId: IdType = @enumFromInt(0);
	const secondId: IdType = @enumFromInt(1);

	set.set(main.heap.testingAllocator, firstId, 5);
	set.set(main.heap.testingAllocator, secondId, expectSecond);

	try set.remove(firstId);

	set.set(main.heap.testingAllocator, firstId, expectNew);

	try std.testing.expectEqual(set.get(secondId).?.*, expectSecond);
	try std.testing.expectEqual(set.get(firstId).?.*, expectNew);
}

// MARK: functionPtrCast()
fn CastFunctionSelfToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	var params = typeInfo.@"fn".params[0..typeInfo.@"fn".params.len].*;
	if(@sizeOf(params[0].type.?) != @sizeOf(*anyopaque) or @alignOf(params[0].type.?) != @alignOf(*anyopaque)) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{params[0].type.?}));
	}
	params[0].type = *anyopaque;
	typeInfo.@"fn".params = params[0..];
	return @Type(typeInfo);
}
/// Turns the first parameter into a anyopaque*
pub fn castFunctionSelfToAnyopaque(function: anytype) *const CastFunctionSelfToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

fn CastFunctionReturnToAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	if(@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) == .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to *anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	typeInfo.@"fn".return_type = *anyopaque;
	return @Type(typeInfo);
}

fn CastFunctionReturnToOptionalAnyopaqueType(Fn: type) type {
	var typeInfo = @typeInfo(Fn);
	if(@sizeOf(typeInfo.@"fn".return_type.?) != @sizeOf(?*anyopaque) or @alignOf(typeInfo.@"fn".return_type.?) != @alignOf(?*anyopaque) or @typeInfo(typeInfo.@"fn".return_type.?) != .optional) {
		@compileError(std.fmt.comptimePrint("Cannot convert {} to ?*anyopaque", .{typeInfo.@"fn".return_type.?}));
	}
	typeInfo.@"fn".return_type = ?*anyopaque;
	return @Type(typeInfo);
}
/// Turns the return parameter into a anyopaque*
pub fn castFunctionReturnToAnyopaque(function: anytype) *const CastFunctionReturnToAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}
pub fn castFunctionReturnToOptionalAnyopaque(function: anytype) *const CastFunctionReturnToOptionalAnyopaqueType(@TypeOf(function)) {
	return @ptrCast(&function);
}

pub fn panicWithMessage(comptime fmt: []const u8, args: anytype) noreturn {
	const message = std.fmt.allocPrint(main.stackAllocator.allocator, fmt, args) catch unreachable;
	@panic(message);
}
