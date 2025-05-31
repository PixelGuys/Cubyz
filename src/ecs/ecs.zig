const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const DynamicPackedIntArray = main.utils.DynamicPackedIntArray;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const SparseSet = main.utils.SparseSet;
const DenseId = main.utils.DenseId;

const ComponentMask = std.StaticBitSet(@typeInfo(component_list).@"struct".decls.len);

pub const component_list = @import("components/_list.zig");

pub const EntityTypeIndex = DenseId(u16);
pub const EntityIndex = DenseId(u16);

const ComponentEnum = std.meta.DeclEnum(component_list);

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var arena: NeverFailingAllocator = undefined;

var freeList: main.ListUnmanaged(EntityIndex) = undefined;

var entityIdToEntityType: std.StringArrayHashMapUnmanaged(EntityTypeIndex) = undefined;
var nextEntityType: u16 = undefined;

var entityIndexToEntityTypeIndex: SparseSet(EntityTypeIndex, EntityIndex) = undefined;

var entitySpawnComponents: SparseSet(ComponentMask, EntityTypeIndex) = undefined;

pub fn init() void {
	arenaAllocator = .init(main.globalAllocator);
	arena = arenaAllocator.allocator();

	nextEntityType = 0;

	freeList = .initCapacity(arena, @intFromEnum(EntityIndex.noValue));

	for(0..@intFromEnum(EntityIndex.noValue)) |i| {
		freeList.append(arena, @enumFromInt(@intFromEnum(EntityIndex.noValue) - i - 1));
	}

	entityIdToEntityType = .{};
	entityIndexToEntityTypeIndex = .{};
	entitySpawnComponents = .{};

	inline for(@typeInfo(component_list).@"struct".decls) |decl| {
		@field(component_list, decl.name).init();
	}
}

pub fn deinit() void {
	inline for(@typeInfo(component_list).@"struct".decls) |decl| {
		@field(component_list, decl.name).deinit(main.globalAllocator);
	}

	arenaAllocator.deinit();
}

pub fn reset() void {
	inline for(@typeInfo(component_list).@"struct".decls) |decl| {
		@field(component_list, decl.name).reset();
	}

	freeList = .initCapacity(arena, @intFromEnum(EntityIndex.noValue));

	for(0..@intFromEnum(EntityIndex.noValue)) |i| {
		freeList.append(arena, @enumFromInt(@intFromEnum(EntityIndex.noValue) - i - 1));
	}

	_ = arenaAllocator.reset(.free_all);
	
	entityIdToEntityType = .{};
	entityIndexToEntityTypeIndex = .{};
	entitySpawnComponents = .{};
	freeList = .{};
}

pub fn hasRegistered(id: []const u8) bool {
	return entityIdToEntityType.contains(id);
}

pub fn getTypeById(id: []const u8) EntityTypeIndex {
	return entityIdToEntityType.get(id) orelse {
		std.log.err("Entity type {s} not found, replacing with noValue", .{id});
		return .noValue;
	};
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) void {
	const componentMap = zon.getChild("components");

	if(componentMap != .object) {
		std.log.err("components must be an object, not a {s}", .{@tagName(componentMap)});
		return;
	}

	defer nextEntityType += 1;

	var iterator = componentMap.object.iterator();
	while(iterator.next()) |entry| {
		const componentId = entry.key_ptr.*;
		const value = entry.value_ptr.*;

		const component = std.meta.stringToEnum(ComponentEnum, componentId) orelse {
			std.log.err("{s} is not a valid component", .{componentId});
			continue;
		};

		switch(component) {
			inline else => |comp| {
				@field(component_list, @tagName(comp)).initType(main.globalAllocator, @enumFromInt(nextEntityType), value);
			},
		}
	}

	entityIdToEntityType.put(arena.allocator, id, @enumFromInt(nextEntityType)) catch unreachable;

	var spawnComponents: ComponentMask = .initEmpty();

	const spawnComponentsList = zon.getChild("spawnComponents");
	if(spawnComponentsList != .array) {
		std.log.err("spawnComponents must be an array, not a {s}", .{@tagName(spawnComponentsList)});
		return;
	}

	for(spawnComponentsList.array.items) |item| {
		const componentId = item.as(?[]const u8, null) orelse {
			std.log.err("spawnComponents must only contain strings", .{});
			continue;
		};

		const component = std.meta.stringToEnum(ComponentEnum, componentId) orelse {
			std.log.err("{s} is not a valid component", .{componentId});
			continue;
		};

		switch(component) {
			inline else => |comp| {
				if(!@field(component_list, @tagName(comp)).hasType(@enumFromInt(nextEntityType))) {
					std.log.err("Component type {s} is not initialized for entity type {s}", .{componentId, id});
					continue;
				}
			},
		}

		spawnComponents.set(@intFromEnum(component));
	}

	entitySpawnComponents.set(arena, @enumFromInt(nextEntityType), spawnComponents);
}

pub fn createEntity(id: []const u8) !EntityIndex {
	const entityIndex = freeList.popOrNull() orelse {
		return error.EntityPoolExhausted;
	};

	const entityTypeIndex = entityIdToEntityType.get(id) orelse {
		return error.InvalidEntityType;
	};

	const spawnComponents = entitySpawnComponents.get(entityTypeIndex) orelse unreachable;

	var iterator = spawnComponents.iterator(.{});
	while(iterator.next()) |component| {
		const componentFlag: ComponentEnum = @enumFromInt(component);

		switch(componentFlag) {
			inline else => |comp| {
				@field(component_list, @tagName(comp)).add(main.globalAllocator, entityIndex, entityTypeIndex);
			},
		}
	}

	entityIndexToEntityTypeIndex.set(arena, entityIndex, entityTypeIndex);

	return entityIndex;
}

pub fn removeEntity(entityIndex: EntityIndex) !void {
	const entityTypeIndexPtr = entityIndexToEntityTypeIndex.get(entityIndex) orelse {
		return error.InvalidEntityType;
	};

	const entityTypeIndex = entityTypeIndexPtr.*;

	inline for(@typeInfo(component_list).@"struct".decls) |decl| {
		const comp = @field(component_list, decl.name);
		if(comp.has(entityIndex)) {
			try comp.remove(main.globalAllocator, entityIndex, entityTypeIndex);
		}
	}

	try entityIndexToEntityTypeIndex.remove(entityIndex);

	freeList.append(arena, entityIndex);
}
