const std = @import("std");

const main = @import("main.zig");
const List = main.List;
const Vec3i = main.vec.Vec3i;
const Block = main.blocks.Block;
const Chunk = main.chunk.Chunk;
const ChunkPosition = main.chunk.ChunkPosition;
const getIndex = main.chunk.getIndex;
const server = main.server;

pub const EntityDataClass = struct {
	id: []const u8,
	vtable: VTable,
	mutex: std.Thread.Mutex,

	const VTable = struct {
		deinit: *const fn() void,
		reset: *const fn() void,
		add: *const fn(pos: Vec3i, value: *anyopaque, chunk: *Chunk) void,
		remove: *const fn(pos: Vec3i, chunk: *Chunk) void,
		get: *const fn(pos: Vec3i, chunk: *Chunk) *anyopaque,
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
	pub inline fn deinit(self: *EntityDataClass) void {
		self.vtable.deinit();
	}
	pub inline fn reset(self: *EntityDataClass) void {
		self.vtable.reset();
	}
	pub inline fn add(self: *EntityDataClass, pos: Vec3i, value: *anyopaque, chunk: *Chunk) void {
		return self.vtable.add(pos, value, chunk);
	}
	pub inline fn remove(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) void {
		return self.vtable.remove(pos, chunk);
	}
	pub inline fn get(self: *EntityDataClass, pos: Vec3i, chunk: *Chunk) *anyopaque {
		return self.vtable.get(pos, chunk);
	}
};

fn BlockEntityData(comptime entityId: []const u8, T: type) type {
	return struct {
		pub const id = entityId;
		pub const DataT = T;
		pub const EntryT = struct {
			absoluteBlockPosition: Vec3i,
			data: DataT,
		};
		var storage: List(EntryT) = undefined;

		fn init() void {
			storage = .init(main.globalAllocator);
		}
		fn deinit() void {
			storage.deinit();
		}
		fn reset() void {
			storage.clearRetainingCapacity();
		}
		fn add(pos: Vec3i, value: *DataT, chunk: *Chunk) void {
			const dataIndex = storage.len;
			storage.append(pos, EntryT{.absoluteBlockPosition = pos, .data = value.*});

			const blockIndex = chunk.getLocalBlockIndex(pos);
			chunk.blockPosToEntityDataMap.put(main.globalAllocator.allocator, blockIndex, dataIndex);
		}
		fn remove(pos: Vec3i, chunk: *Chunk) void {
			const blockIndex = chunk.getLocalBlockIndex(pos);
			const dataIndex = chunk.blockPosToEntityDataMap.fetchRemove(blockIndex) orelse {
				std.log.err("Couldn't remove entity data of block at position {}", .{pos});
				return;
			};
			_ = storage.swapRemove(dataIndex);
			if(dataIndex == storage.items.len) return null;

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
			const dataIndex = chunk.blockPosToEntityDataMap.get(blockIndex) orelse return null;
			return &storage.items[dataIndex].data;
		}
	};
}

pub const EntityDataClasses = struct {
	pub const Chest = BlockEntityData(struct {
		contents: u64,
	});
	pub const Door = BlockEntityData(struct {
		open: bool,
	});
};

var entityDataClasses: std.StringHashMapUnmanaged(EntityDataClass) = .{};

pub fn init() void {
	inline for(@typeInfo(EntityDataClasses).@"struct".decls) |declaration| {
		const class = EntityDataClass.init(@field(EntityDataClasses, declaration.name));
		entityDataClasses.putNoClobber(main.globalAllocator.allocator, class.id, class) catch unreachable;
	}
}

pub fn reset() void {
	var iterator = entityDataClasses.iterator();
	while(iterator.next()) |entry| {
		entry.value_ptr.reset();
	}
}

pub fn deinit() void {
	var iterator = entityDataClasses.iterator();
	while(iterator.next()) |entry| {
		entry.value_ptr.deinit();
	}
	entityDataClasses.deinit(main.globalAllocator.allocator);
}

pub fn getByID(id: []const u8) ?*EntityDataClass {
	if(std.mem.eql(u8, id, "")) return null;
	if(entityDataClasses.getPtr(id)) |cls| return cls;
	std.log.err("EntityDataClass with id '{s}' not found", .{id});
	return null;
}
