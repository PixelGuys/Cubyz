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
		onLoad: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onUnload: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onPlace: *const fn(pos: Vec3i, chunk: *Chunk) void,
		onBreak: *const fn(pos: Vec3i, chunk: *Chunk) void,
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
	pub inline fn onLoad(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onLoad(pos, chunk);
	}
	pub inline fn onUnload(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onUnload(pos, chunk);
	}
	pub inline fn onPlace(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onPlace(pos, chunk);
	}
	pub inline fn onBreak(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		self.mutex.lock();
		defer self.mutex.unlock();
		return self.vtable.onBreak(pos, chunk);
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
				std.log.err("Couldn't remove entity data of block at position {}", .{pos});
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
		fn get(pos: Vec3i, chunk: *Chunk) *DataT {
			const blockIndex = chunk.getLocalBlockIndex(pos);
			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse unreachable;
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

		pub fn onLoad(pos: Vec3i, chunk: *Chunk) void {
			Super.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onUnload(pos: Vec3i, chunk: *Chunk) void {
			Super.remove(pos, chunk);
		}
		pub fn onPlace(pos: Vec3i, chunk: *Chunk) void {
			Super.add(pos, .{.contents = 0}, chunk);
		}
		pub fn onBreak(pos: Vec3i, chunk: *Chunk) void {
			Super.remove(pos, chunk);
		}
		pub fn onInteract(pos: Vec3i, chunk: *Chunk) bool {
			const data = Super.get(pos, chunk);
			std.debug.print("Chest contents: {}", .{data.contents});
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
