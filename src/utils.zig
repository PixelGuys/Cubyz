const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("main.zig");

pub const Compression = struct {
	pub fn deflate(allocator: Allocator, data: []const u8) ![]u8 {
		var result = std.ArrayList(u8).init(allocator);
		var comp = try std.compress.deflate.compressor(main.threadAllocator, result.writer(), .{.level = .default_compression});
		try comp.write(data);
		try comp.close();
		comp.deinit();
		return result.toOwnedSlice();
	}

	pub fn inflate(allocator: Allocator, data: []const u8) ![]u8 {
		var stream = std.io.fixedBufferStream(data);
		var decomp = try std.compress.deflate.decompressor(main.threadAllocator, stream.reader(), null);
		defer decomp.deinit();
		return try decomp.reader().readAllAlloc(allocator, std.math.maxInt(usize));
	}

	pub fn pack(sourceDir: std.fs.IterableDir, writer: anytype) !void {
		var comp = try std.compress.deflate.compressor(main.threadAllocator, writer, .{.level = .default_compression});
		defer comp.deinit();
		var walker = try sourceDir.walk(main.threadAllocator);
		defer walker.deinit();

		while(try walker.next()) |entry| {
			if(entry.kind == .File) {
				var relPath = entry.path;
				var len: [4]u8 = undefined;
				std.mem.writeIntBig(u32, &len, @intCast(u32, relPath.len));
				_ = try comp.write(&len);
				_ = try comp.write(relPath);

				var file = try sourceDir.dir.openFile(relPath, .{});
				defer file.close();
				var fileData = try file.readToEndAlloc(main.threadAllocator, std.math.maxInt(u32));
				defer main.threadAllocator.free(fileData);

				std.mem.writeIntBig(u32, &len, @intCast(u32, fileData.len));
				_ = try comp.write(&len);
				_ = try comp.write(fileData);
			}
		}
		try comp.close();
	}

	pub fn unpack(outDir: std.fs.Dir, input: []const u8) !void {
		var stream = std.io.fixedBufferStream(input);
		var decomp = try std.compress.deflate.decompressor(main.threadAllocator, stream.reader(), null);
		defer decomp.deinit();
		var reader = decomp.reader();
		const _data = try reader.readAllAlloc(main.threadAllocator, std.math.maxInt(usize));
		defer main.threadAllocator.free(_data);
		var data = _data;
		while(data.len != 0) {
			var len = std.mem.readIntBig(u32, data[0..4]);
			data = data[4..];
			var path = data[0..len];
			data = data[len..];
			len = std.mem.readIntBig(u32, data[0..4]);
			data = data[4..];
			var fileData = data[0..len];
			data = data[len..];

			var splitter = std.mem.splitBackwards(u8, path, "/");
			_ = splitter.first();
			try outDir.makePath(splitter.rest());
			var file = try outDir.createFile(path, .{});
			defer file.close();
			try file.writeAll(fileData);
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
			var self = try allocator.create(@This());
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
			var i = _i;
			while(2*i + 2 < self.size) {
				var biggest = if(self.array[2*i + 1].biggerThan(self.array[2*i + 2])) 2*i + 1 else 2*i + 2;
				// Break if all childs are smaller.
				if(self.array[i].biggerThan(self.array[biggest])) return;
				// Swap it:
				var local = self.array[biggest];
				self.array[biggest] = self.array[i];
				self.array[i] = local;
				// goto the next node:
				i = biggest;
			}
		}

		/// Moves an element from a given index up the heap, such that all children are always smaller than their parents.
		fn siftUp(self: *@This(), _i: usize) void {
			var i = _i;
			var parentIndex = (i - 1)/2;
			while(self.array[i].biggerThan(self.array[parentIndex]) and i > 0) {
				var local = self.array[parentIndex];
				self.array[parentIndex] = self.array[i];
				self.array[i] = local;
				i = parentIndex;
				parentIndex = (i - 1)/2;
			}
		}

		/// Needs to be called after updating the priority of all elements.
		pub fn updatePriority(self: *@This()) void {
			self.mutex.lock();
			defer self.mutex.unlock();
			for(self.array[0..self.size/2]) |_, i| {
				self.siftDown(i);
			}
		}

		/// Returns the i-th element in the heap. Useless for most applications.
		pub fn get(self: *@This(), i: usize) ?T {
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
					var ret = self.array[0];
					self.removeIndex(0);
					return ret;
				}
				if(self.closed) {
					return error.Closed;
				}
			}
		}

		fn increaseCapacity(self: *@This(), newCapacity: usize) !void {
			self.array = self.allocator.realloc(self.array, newCapacity);
		}
	};
}

pub const ThreadPool = struct {
	const Task = struct {
		cachedPriority: f32,
		self: *anyopaque,
		vtable: *VTable,

		fn biggerThan(self: Task, other: Task) bool {
			return self.cachedPriority > other.cachedPriority;
		}
	};
	pub const VTable = struct {
		getPriority: *const fn(*anyopaque) f32,
		isStillNeeded: *const fn(*anyopaque) bool,
		run: *const fn(*anyopaque) void,
		clean: *const fn(*anyopaque) void,
	};
	const refreshTime: u32 = 100; // The time after which all priorities get refreshed in milliseconds.

	threads: []std.Thread,
	loadList: *BlockingMaxHeap(Task),
	allocator: Allocator,

	pub fn init(allocator: Allocator, threadCount: usize) !ThreadPool {
		var self = ThreadPool {
			.threads = try allocator.alloc(std.Thread, threadCount),
			.loadList = try BlockingMaxHeap(Task).init(allocator),
			.allocator = allocator,
		};
		for(self.threads) |*thread, i| {
			thread.* = try std.Thread.spawn(.{}, run, .{self});
			var buf: [64]u8 = undefined;
			try thread.setName(try std.fmt.bufPrint(&buf, "Worker Thread {}", .{i+1}));
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
		self.allocator.free(self.threads);
	}

	fn run(self: ThreadPool) void {
		// In case any of the tasks wants to allocate memory:
		var gpa = std.heap.GeneralPurposeAllocator(.{.thread_safe=false}){};
		main.threadAllocator = gpa.allocator();
		defer if(gpa.deinit()) {
			@panic("Memory leak");
		};

		var lastUpdate = std.time.milliTimestamp();
		while(true) {
			{
				var task = self.loadList.extractMax() catch break;
				task.vtable.run(task.self);
			}

			if(std.time.milliTimestamp() -% lastUpdate > refreshTime) {
				lastUpdate = std.time.milliTimestamp();
				if(self.loadList.mutex.tryLock()) {
					defer self.loadList.mutex.unlock();
					var i: u32 = 0;
					while(i < self.loadList.size) {
						var task = &self.loadList.array[i];
						if(!task.vtable.isStillNeeded(task.self)) {
							self.loadList.removeIndex(i);
							task.vtable.clean(task.self);
						} else {
							task.cachedPriority = task.vtable.getPriority(task.self);
							i += 1;
						}
					}
					self.loadList.updatePriority();
				}
			}
		}
	}

	pub fn addTask(self: ThreadPool, task: *anyopaque, vtable: *VTable) !void {
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