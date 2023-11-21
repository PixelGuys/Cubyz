const std = @import("std");
const Allocator = std.mem.Allocator;
const Atomic = std.atomic.Atomic;
const builtin = @import("builtin");

const main = @import("main.zig");

pub const Compression = struct {
	pub fn deflate(allocator: Allocator, data: []const u8) ![]u8 {
		var result = std.ArrayList(u8).init(allocator);
		var comp = try std.compress.deflate.compressor(main.globalAllocator, result.writer(), .{.level = .default_compression});
		_ = try comp.write(data);
		try comp.close();
		comp.deinit();
		return result.toOwnedSlice();
	}

	pub fn inflateTo(buf: []u8, data: []const u8) !usize {
		var arena = std.heap.ArenaAllocator.init(main.stackAllocator);
		defer arena.deinit();
		var stream = std.io.fixedBufferStream(data);
		var decomp = try std.compress.deflate.decompressor(arena.allocator(), stream.reader(), null);
		defer decomp.deinit();
		return try decomp.reader().readAll(buf);
	}

	pub fn pack(sourceDir: std.fs.IterableDir, writer: anytype) !void {
		var comp = try std.compress.deflate.compressor(main.globalAllocator, writer, .{.level = .default_compression});
		defer comp.deinit();
		var walker = try sourceDir.walk(main.globalAllocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .file) {
				var relPath = entry.path;
				if(builtin.os.tag == .windows) { // I hate you
					const copy = try main.stackAllocator.dupe(u8, relPath);
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

				const file = try sourceDir.dir.openFile(relPath, .{});
				defer file.close();
				const fileData = try file.readToEndAlloc(main.stackAllocator, std.math.maxInt(u32));
				defer main.stackAllocator.free(fileData);

				std.mem.writeInt(u32, &len, @as(u32, @intCast(fileData.len)), .big);
				_ = try comp.write(&len);
				_ = try comp.write(fileData);
			}
		}
		try comp.close();
	}

	pub fn unpack(outDir: std.fs.Dir, input: []const u8) !void {
		var stream = std.io.fixedBufferStream(input);
		var decomp = try std.compress.deflate.decompressor(main.globalAllocator, stream.reader(), null);
		defer decomp.deinit();
		const reader = decomp.reader();
		const _data = try reader.readAllAlloc(main.stackAllocator, std.math.maxInt(usize));
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

			var splitter = std.mem.splitBackwards(u8, path, "/");
			_ = splitter.first();
			try outDir.makePath(splitter.rest());
			const file = try outDir.createFile(path, .{});
			defer file.close();
			try file.writeAll(fileData);
		}
	}
};

/// Implementation of https://en.wikipedia.org/wiki/Alias_method
pub fn AliasTable(comptime T: type) type {
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

		pub fn init(allocator: Allocator, items: []T) !@This() {
			var self: @This() = .{
				.items = items,
				.aliasData = try allocator.alloc(AliasData, items.len),
			};
			if(items.len == 0) return self;
			@memset(self.aliasData, AliasData{.chance = 0, .alias = 0});
			const currentChances = try main.stackAllocator.alloc(f32, items.len);
			defer main.stackAllocator.free(currentChances);
			var totalChance: f32 = 0;
			for(items, 0..) |*item, i| {
				totalChance += item.chance;
				currentChances[i] = item.chance;
			}

			self.initAliasData(totalChance, currentChances);

			return self;
		}

		pub fn initFromContext(allocator: Allocator, slice: anytype) !@This() {
			const items = try allocator.alloc(T, slice.len);
			for(slice, items) |context, *result| {
				result.* = context.getItem();
			}
			var self: @This() = .{
				.items = items,
				.aliasData = try allocator.alloc(AliasData, items.len),
				.ownsSlice = true,
			};
			if(items.len == 0) return self;
			@memset(self.aliasData, AliasData{.chance = 0, .alias = 0});
			const currentChances = try main.stackAllocator.alloc(f32, items.len);
			defer main.stackAllocator.free(currentChances);
			var totalChance: f32 = 0;
			for(slice, 0..) |context, i| {
				totalChance += context.chance;
				currentChances[i] = context.chance;
			}

			self.initAliasData(totalChance, currentChances);

			return self;
		}

		pub fn deinit(self: *const @This(), allocator: Allocator) void {
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
pub fn SortedList(comptime T: type) type {
	return struct {
		const Self = @This();

		ptr: [*]T = undefined,
		len: u32 = 0,
		capacity: u32 = 0,

		pub fn deinit(self: Self, allocator: Allocator) void {
			allocator.free(self.ptr[0..self.capacity]);
		}

		pub fn items(self: Self) []T {
			return self.ptr[0..self.len];
		}

		fn increaseCapacity(self: *Self, allocator: Allocator) !void {
			const newSize = 8 + self.capacity*3/2;
			const newSlice = try allocator.realloc(self.ptr[0..self.capacity], newSize);
			self.capacity = @intCast(newSlice.len);
			self.ptr = newSlice.ptr;
		}

		pub fn insertSorted(self: *Self, allocator: Allocator, object: T) !void {
			if(self.len == self.capacity) {
				try self.increaseCapacity(allocator);
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

		pub fn toOwnedSlice(self: *Self, allocator: Allocator) ![]T {
			const output = try allocator.realloc(self.ptr[0..self.capacity], self.len);
			self.* = .{};
			return output;
		}
	};
}

pub fn Array2D(comptime T: type) type {
	return struct {
		const Self = @This();
		mem: []T,
		width: u32,
		height: u32,

		pub fn init(allocator: Allocator, width: u32, height: u32) !Self {
			return .{
				.mem = try allocator.alloc(T, width*height),
				.width = width,
				.height = height,
			};
		}

		pub fn deinit(self: Self, allocator: Allocator) void {
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

pub fn Array3D(comptime T: type) type {
	return struct {
		const Self = @This();
		mem: []T,
		width: u32,
		height: u32,
		depth: u32,

		pub fn init(allocator: Allocator, width: u32, height: u32, depth: u32) !Self {
			return .{
				.mem = try allocator.alloc(T, width*height*depth),
				.width = width,
				.height = height,
				.depth = depth,
			};
		}

		pub fn deinit(self: Self, allocator: Allocator) void {
			allocator.free(self.mem);
		}

		pub fn get(self: Self, x: usize, y: usize, z: usize) T {
			std.debug.assert(x < self.width and y < self.height and z < self.depth);
			return self.mem[(x*self.height + y)*self.depth + z];
		}

		pub fn set(self: Self, x: usize, y: usize, z: usize, t: T) void {
			std.debug.assert(x < self.width and y < self.height and z < self.depth);
			self.mem[(x*self.height + y)*self.depth + z] = t;
		}

		pub fn ptr(self: Self, x: usize, y: usize, z: usize) *T {
			std.debug.assert(x < self.width and y < self.height and z < self.depth);
			return &self.mem[(x*self.height + y)*self.depth + z];
		}
	};
}

/// Allows for stack-like allocations in a fast and safe way.
/// It is safe in the sense that a regular allocator will be used when the buffer is full.
pub const StackAllocator = struct {
	const Allocation = struct{start: u32, len: u32};
	backingAllocator: Allocator,
	buffer: []align(4096) u8,
	allocationList: std.ArrayList(Allocation),
	index: usize,

	pub fn init(backingAllocator: Allocator, size: u32) !StackAllocator {
		return .{
			.backingAllocator = backingAllocator,
			.buffer = try backingAllocator.alignedAlloc(u8, 4096, size),
			.allocationList = std.ArrayList(Allocation).init(backingAllocator),
			.index = 0,
		};
	}

	pub fn deinit(self: StackAllocator) void {
		if(self.allocationList.items.len != 0) {
			std.log.err("Memory leak in Stack Allocator", .{});
		}
		self.allocationList.deinit();
		self.backingAllocator.free(self.buffer);
	}

	pub fn allocator(self: *StackAllocator) Allocator {
		return .{
			.vtable = &.{
				.alloc = &alloc,
				.resize = &resize,
				.free = &free,
			},
			.ptr = self,
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

    /// Attempt to allocate exactly `len` bytes aligned to `1 << ptr_align`.
    ///
    /// `ret_addr` is optionally provided as the first return address of the
    /// allocation call stack. If the value is `0` it means no return address
    /// has been provided.
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
		const self: *StackAllocator = @ptrCast(@alignCast(ctx));
		if(len >= self.buffer.len) return self.backingAllocator.rawAlloc(len, ptr_align, ret_addr);
		const start = std.mem.alignForward(usize, self.index, @as(usize, 1) << @intCast(ptr_align));
		if(start + len >= self.buffer.len) return self.backingAllocator.rawAlloc(len, ptr_align, ret_addr);
		self.allocationList.append(.{.start = @intCast(start), .len = @intCast(len)}) catch return null;
		self.index = start + len;
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
			const top = &self.allocationList.items[self.allocationList.items.len - 1];
			std.debug.assert(top.start == self.indexInBuffer(buf)); // Can only resize the top element.
			std.debug.assert(top.len == buf.len);
			std.debug.assert(self.index >= top.start + top.len);
			if(top.start + new_len >= self.buffer.len) {
				return false;
			}
			self.index -= top.len;
			self.index += new_len;
			top.len = @intCast(new_len);
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
			const top = self.allocationList.pop();
			std.debug.assert(top.start == self.indexInBuffer(buf)); // Can only free the top element.
			std.debug.assert(top.len == buf.len);
			std.debug.assert(self.index >= top.start + top.len);
			self.index = top.start;
		} else {
			self.backingAllocator.rawFree(buf, buf_align, ret_addr);
		}
	}
};

/// A simple binary heap.
/// Thread safe and blocking.
/// Expects T to have a `biggerThan(T) bool` function
pub fn BlockingMaxHeap(comptime T: type) type {
	return struct {
		const initialSize = 16;
		size: usize,
		array: []T,
		waitingThreads: std.Thread.Condition,
		waitingThreadCount: u32 = 0,
		mutex: std.Thread.Mutex,
		allocator: Allocator,
		closed: bool = false,

		pub fn init(allocator: Allocator) !*@This() {
			const self = try allocator.create(@This());
			self.* = @This() {
				.size = 0,
				.array = try allocator.alloc(T, initialSize),
				.waitingThreads = .{},
				.mutex = .{},
				.allocator = allocator,
			};
			return self;
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
			self.allocator.destroy(self);
		}

		/// Moves an element from a given index down the heap, such that all children are always smaller than their parents.
		fn siftDown(self: *@This(), _i: usize) void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
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
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
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
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
			if(i >= self.size) return null;
			return self.array[i];
		}

		/// Adds a new element to the heap.
		pub fn add(self: *@This(), elem: T) !void {
			self.mutex.lock();
			defer self.mutex.unlock();

			if(self.size == self.array.len) {
				try self.increaseCapacity(self.size*2);
			}
			self.array[self.size] = elem;
			self.siftUp(self.size);
			self.size += 1;

			self.waitingThreads.signal();
		}

		fn removeIndex(self: *@This(), i: usize) void {
			std.debug.assert(!self.mutex.tryLock()); // The mutex should be locked when calling this function.
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

		fn increaseCapacity(self: *@This(), newCapacity: usize) !void {
			self.array = try self.allocator.realloc(self.array, newCapacity);
		}
	};
}

pub const ThreadPool = struct {
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
		run: *const fn(*anyopaque) Allocator.Error!void,
		clean: *const fn(*anyopaque) void,
	};
	const refreshTime: u32 = 100; // The time after which all priorities get refreshed in milliseconds.

	threads: []std.Thread,
	currentTasks: []std.atomic.Atomic(?*const VTable),
	loadList: *BlockingMaxHeap(Task),
	allocator: Allocator,

	pub fn init(allocator: Allocator, threadCount: usize) !ThreadPool {
		const self = ThreadPool {
			.threads = try allocator.alloc(std.Thread, threadCount),
			.currentTasks = try allocator.alloc(std.atomic.Atomic(?*const VTable), threadCount),
			.loadList = try BlockingMaxHeap(Task).init(allocator),
			.allocator = allocator,
		};
		for(self.threads, 0..) |*thread, i| {
			thread.* = try std.Thread.spawn(.{}, run, .{self, i});
			var buf: [64]u8 = undefined;
			thread.setName(try std.fmt.bufPrint(&buf, "Worker {}", .{i+1})) catch |err| std.log.err("Couldn't rename thread: {s}", .{@errorName(err)});
		}
		return self;
	}

	pub fn deinit(self: ThreadPool) void {
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
	}

	pub fn closeAllTasksOfType(self: ThreadPool, vtable: *const VTable) void {
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
			while(task.load(.Monotonic) == vtable) {
				std.time.sleep(1e6);
			}
		}
	}

	fn run(self: ThreadPool, id: usize) !void {
		// In case any of the tasks wants to allocate memory:
		var sta = try StackAllocator.init(main.globalAllocator, 1 << 23);
		defer sta.deinit();
		main.stackAllocator = sta.allocator();

		var lastUpdate = std.time.milliTimestamp();
		while(true) {
			{
				const task = self.loadList.extractMax() catch break;
				self.currentTasks[id].store(task.vtable, .Monotonic);
				try task.vtable.run(task.self);
				self.currentTasks[id].store(null, .Monotonic);
			}

			if(std.time.milliTimestamp() -% lastUpdate > refreshTime) {
				if(self.loadList.mutex.tryLock()) {
					lastUpdate = std.time.milliTimestamp();
					{
						defer self.loadList.mutex.unlock();
						var i: u32 = 0;
						while(i < self.loadList.size) {
							const task = &self.loadList.array[i];
							if(!task.vtable.isStillNeeded(task.self)) {
								task.vtable.clean(task.self);
								self.loadList.removeIndex(i);
							} else {
								task.cachedPriority = task.vtable.getPriority(task.self);
								i += 1;
							}
						}
					}
					self.loadList.updatePriority();
				}
			}
		}
	}

	pub fn addTask(self: ThreadPool, task: *anyopaque, vtable: *const VTable) !void {
		try self.loadList.add(Task {
			.cachedPriority = vtable.getPriority(task),
			.vtable = vtable,
			.self = task,
		});
	}

	pub fn clear(self: ThreadPool) void {
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

	pub fn queueSize(self: ThreadPool) usize {
		self.loadList.mutex.lock();
		defer self.loadList.mutex.unlock();
		return self.loadList.size;
	}
};

/// Implements a simple set associative cache with LRU replacement strategy.
pub fn Cache(comptime T: type, comptime numberOfBuckets: u32, comptime bucketSize: u32, comptime deinitFunction: fn(*T) void) type {
	const hashMask = numberOfBuckets-1;
	if(numberOfBuckets & hashMask != 0) @compileError("The number of buckets should be a power of 2!");

	const Bucket = struct {
		mutex: std.Thread.Mutex = .{},
		items: [bucketSize]?*T = [_]?*T {null} ** bucketSize,

		fn find(self: *@This(), compare: anytype) ?*T {
			std.debug.assert(!self.mutex.tryLock()); // The mutex must be locked.
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
			std.debug.assert(!self.mutex.tryLock()); // The mutex must be locked.
			const previous = self.items[bucketSize - 1];
			std.mem.copyBackwards(?*T, self.items[1..], self.items[0..bucketSize - 1]);
			self.items[0] = item;
			return previous;
		}

		fn findOrCreate(self: *@This(), compare: anytype, comptime initFunction: fn(@TypeOf(compare)) Allocator.Error!*T) Allocator.Error!*T {
			std.debug.assert(!self.mutex.tryLock()); // The mutex must be locked.
			if(self.find(compare)) |item| {
				return item;
			}
			const new = try initFunction(compare);
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
		cacheRequests: Atomic(usize) = Atomic(usize).init(0),
		cacheMisses: Atomic(usize) = Atomic(usize).init(0),

		///  Tries to find the entry that fits to the supplied hashable.
		pub fn find(self: *@This(), compareAndHash: anytype) ?*T {
			const index: u32 = compareAndHash.hashCode() & hashMask;
			_ = @atomicRmw(usize, &self.cacheRequests.value, .Add, 1, .Monotonic);
			self.buckets[index].mutex.lock();
			defer self.buckets[index].mutex.unlock();
			if(self.buckets[index].find(compareAndHash)) |item| {
				return item;
			}
			_ = @atomicRmw(usize, &self.cacheMisses.value, .Add, 1, .Monotonic);
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

		pub fn findOrCreate(self: *@This(), compareAndHash: anytype, comptime initFunction: fn(@TypeOf(compareAndHash)) Allocator.Error!*T) Allocator.Error!*T {
			const index: u32 = compareAndHash.hashCode() & hashMask;
			self.buckets[index].mutex.lock();
			defer self.buckets[index].mutex.unlock();
			return try self.buckets[index].findOrCreate(compareAndHash, initFunction);
		}
	};
}

///  https://en.wikipedia.org/wiki/Cubic_Hermite_spline#Unit_interval_(0,_1)
pub fn unitIntervalSpline(comptime Float: type, p0: Float, m0: Float, p1: Float, m1: Float) [4]Float {
	return .{
		p0,
		m0,
		-3*p0 - 2*m0 + 3*p1 - m1,
		2*p0 + m0 - 2*p1 + m1,
	};
}

pub fn GenericInterpolation(comptime elements: comptime_int) type {
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
					//                     ↓ Only using a future time value that is far enough away to prevent jumping.
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

pub const TimeDifference = struct {
	difference: Atomic(i16) = Atomic(i16).init(0),
	firstValue: bool = true,

	pub fn addDataPoint(self: *TimeDifference, time: i16) void {
		const currentTime: i16 = @truncate(std.time.milliTimestamp());
		const timeDifference = currentTime -% time;
		if(self.firstValue) {
			self.difference.store(timeDifference, .Monotonic);
			self.firstValue = false;
		}
		if(timeDifference -% self.difference.load(.Monotonic) > 0) {
			_ = @atomicRmw(i16, &self.difference.value, .Add, 1, .Monotonic);
		} else if(timeDifference -% self.difference.load(.Monotonic) < 0) {
			_ = @atomicRmw(i16, &self.difference.value, .Add, -1, .Monotonic);
		}
	}
};