const std = @import("std");

const main = @import("main.zig");
const List = main.List;
const Vec3i = main.vec.Vec3i;
const Block = main.blocks.Block;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const getIndex = main.chunk.getIndex;
const server = main.server;
const User = server.User;

pub const EntityDataClass = struct {
	id: []const u8,
	vtable: VTable,
	mutex: std.Thread.Mutex,

	const VTable = struct {
		onLoadClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onLoadServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnloadServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakClient: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlaceServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreakServer: *const fn(pos: Vec3i, chunk: *Chunk) void,
		// Block interaction invoked by right click.
		// Return value indicates if event was handled (true) and should not be further processed.
		onInteract: *const fn(pos: Vec3i, chunk: *Chunk) bool,
	};
	pub fn init(comptime EntityDataClassT: type) EntityDataClass {
		EntityDataClassT.init();
		var class = EntityDataClass{
			.id = EntityDataClassT.id,
			.vtable = undefined,
			.mutex = .{},
		};

		inline for(@typeInfo(EntityDataClass.VTable).@"struct".fields) |field| {
			if(!@hasDecl(EntityDataClassT, field.name)) {
				@compileError("EntityDataClass missing field");
			}
			@field(class.vtable, field.name) = @ptrCast(&@field(EntityDataClassT, field.name));
		}
		return class;
	}
	pub inline fn onLoadClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onLoadClient(pos, chunk);
	}
	pub inline fn onUnloadClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onUnloadClient(pos, chunk);
	}
	pub inline fn onLoadServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onLoadServer(pos, chunk);
	}
	pub inline fn onUnloadServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onUnloadServer(pos, chunk);
	}
	pub inline fn onPlaceClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onPlaceClient(pos, chunk);
	}
	pub inline fn onBreakClient(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onBreakClient(pos, chunk);
	}
	pub inline fn onPlaceServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onPlaceServer(pos, chunk);
	}
	pub inline fn onBreakServer(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onBreakServer(pos, chunk);
	}
	pub inline fn onInteract(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) bool {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onInteract(pos, chunk);
	}
};

fn BlockEntityData(T: type) type {
	return struct {
		pub const DataT = T;
		pub const EntryT = struct {
			absoluteBlockPosition: Vec3i,
			data: DataT,
		};
		pub var storage: List(EntryT) = undefined;

		fn init() void {
			storage = .init(main.globalAllocator);
		}
		fn deinit() void {
			storage.deinit();
		}
		fn reset() void {
			storage.clearRetainingCapacity();
		}
		fn add(pos: Vec3i, value: DataT, chunk: *Chunk) void {
			const dataIndex = storage.items.len;
			storage.append(.{.absoluteBlockPosition = pos, .data = value});

			const blockIndex = chunk.getLocalBlockIndex(pos);
			chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, blockIndex, @intCast(dataIndex)) catch unreachable;
		}
		fn remove(pos: Vec3i, chunk: *Chunk) void {
			const blockIndex = chunk.getLocalBlockIndex(pos);
			const entry = chunk.blockPosToEntityDataMap.fetchRemove(blockIndex) orelse {
				std.log.warn("Couldn't remove entity data of block at position {}", .{pos});
				return;
			};
			const dataIndex = entry.value;

			_ = storage.swapRemove(dataIndex);
			if(dataIndex == storage.items.len) return;

			const movedEntry = storage.items[dataIndex];

			const otherChunk = server.world.?.getOrGenerateChunkAndIncreaseRefCount(ChunkPosition.initFromWorld(pos, 1));
			defer otherChunk.decreaseRefCount();

			const otherBlockIndex = chunk.getLocalBlockIndex(pos);
			const valuePtr = otherChunk.super.blockPosToEntityDataMap.getPtr(otherBlockIndex) orelse {
				std.log.err("Couldn't update entity data of block at position {}", .{movedEntry.absoluteBlockPosition});
				return;
			};

			valuePtr.* = dataIndex;
		}
		fn get(pos: Vec3i, chunk: *Chunk) ?*DataT {
			const blockIndex = chunk.getLocalBlockIndex(pos);
			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse {
				std.log.warn("Couldn't get entity data of block at position {}", .{pos});
				return null;
			};
			return &storage.items[dataIndex].data;
		}
	};
}

pub const EntityDataClasses = struct {
	pub const Chest = struct {
		const Super = BlockEntityData(
			struct {
				contents: u64,
			},
		);

		pub const id = "chest";
		const init = Super.init;
		const reset = Super.reset;
		const deinit = Super.deinit;

		pub fn onLoadClient(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onLoadClient", .{});
		}
		pub fn onUnloadClient(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onUnloadClient", .{});
		}
		pub fn onLoadServer(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onLoadServer", .{});
		}
		pub fn onUnloadServer(_: Vec3i, _: *Chunk) void {
			std.log.debug("Chest.onUnloadServer", .{});
		}
		pub fn onPlaceClient(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onPlaceClient", .{});
			Super.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onBreakClient(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onBreakClient", .{});
			Super.remove(pos, chunk);
		}
		pub fn onPlaceServer(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onPlaceServer", .{});
			Super.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onBreakServer(pos: Vec3i, chunk: *Chunk) void {
			std.log.debug("Chest.onBreakServer", .{});
			Super.remove(pos, chunk);
		}
		pub fn onInteract(pos: Vec3i, chunk: *Chunk) bool {
			const data = Super.get(pos, chunk);
			if(data == null) std.log.debug("Chest.onInteract: null", .{})
			else std.log.debug("Chest.onInteract: {}", .{data.?.contents});

			return true;
		}
	};
};

var entityDataClasses: std.StringHashMapUnmanaged(EntityDataClass) = .{};

pub fn init() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		const class = EntityDataClass.init(@field(EntityDataClasses, declaration.name));
		entityDataClasses.putNoClobber(main.globalAllocator.allocator, class.id, class) catch unreachable;
		std.log.debug("Registered EntityDataClass '{s}'", .{class.id});
	}
}

pub fn reset() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		@field(EntityDataClasses, declaration.name).reset();
	}
}

pub fn deinit() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		@field(EntityDataClasses, declaration.name).deinit();
	}
}

pub fn getByID(id: []const u8) ?*EntityDataClass {
	if(std.mem.eql(u8, id, "")) return null;
	if(entityDataClasses.getPtr(id)) |cls| return cls;
	std.log.err("EntityDataClass with id '{s}' not found", .{id});
	return null;
}
