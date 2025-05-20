const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const DynamicPackedIntArray = main.utils.DynamicPackedIntArray;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const SparseSet = main.utils.SparseSet;
const DenseId = main.utils.DenseId;

const components = @import("components/_list.zig");

const ComponentEnum = std.meta.DeclEnum(components);

pub const EntityTypeIndex = DenseId(u16);
pub const EntityIndex = DenseId(u16);

const FeatureMask = @Type(.{.int = .{.bits = std.meta.declarations(components).len, .signedness = .unsigned}});

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var allocator: NeverFailingAllocator = undefined;

const freeList: main.ListUnmanaged(EntityIndex) = undefined;

var entityTypeList: main.ListUnmanaged(EntityType) = undefined;
var entityIdToEntityType: std.StringArrayHashMapUnmanaged(*const EntityType) = undefined;
var nextEntityType: u16 = undefined;

var entityIndexToEntityTypeIndex: SparseSet(EntityTypeIndex, EntityType) = undefined;

const EntityType = struct {
	index: EntityTypeIndex,
	features: FeatureMask,
};

pub fn init() void {
	arenaAllocator = .init(main.globalAllocator);
	allocator = arenaAllocator.allocator();

	nextEntityType = 0;

	freeList = .initCapacity(allocator, @intFromEnum(EntityIndex.noValue));

	for(0..@intFromEnum(EntityIndex.noValue)) |i| {
		freeList.append(allocator, @enumFromInt(@intFromEnum(EntityIndex.noValue) - i - 1));
	}

	entityTypeList = .{};
	entityIdToEntityType = .{};
	entityIndexToEntityTypeIndex = .{};

	inline for(std.meta.declarations(components)) |decl| {
		@field(components, decl.name).init();
	}
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) void {
	const componentMap = zon.getChild("components");

	if(componentMap != .object) {
		std.log.err("components must be an object, not a {s}", .{@tagName(componentMap)});
		return;
	}

	defer nextEntityType += 1;

	var featureMask: FeatureMask = 0;

	const iterator = componentMap.object.iterator();
	while(iterator.next()) |entry| {
		const component = entry.key_ptr.*;
		const value = entry.value_ptr.*;

		const componentType = std.meta.stringToEnum(ComponentEnum, component) orelse {
			std.log.err("{s} is not a valid component", .{component});
			continue;
		};

		featureMask |= 1 << @intFromEnum(componentType);

		switch(componentType) {
			inline else => |typ| {
				@field(components, @tagName(typ)).initType(main.globalAllocator, @enumFromInt(nextEntityType), value);
			},
		}
	}

	entityTypeList.append(allocator, .{
		.index = nextEntityType,
		.features = featureMask,
	});
	entityIdToEntityType.put(allocator, id, &entityTypeList.items[nextEntityType]);
}

pub fn createEntity(id: []const u8) !EntityIndex {
	const entityIndex = freeList.popOrNull() orelse {
		return error.EntityPoolExhausted;
	};

	const entityType = entityIdToEntityType.get(id) orelse {
		return error.InvalidEntityType;
	};

	for(std.meta.declarations(components), 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 0) {
			continue;
		}

		@field(components, decl.name).initData(main.globalAllocator, entityIndex, entityType.index);
	}

	entityIndexToEntityTypeIndex.set(allocator, entityIndex, entityType.index);

	return entityIndex;
}

pub fn removeEntity(entityIndex: EntityIndex) void {
	const entityTypeIndex = entityIndexToEntityTypeIndex.get(entityIndex) orelse {
		return error.InvalidEntityType;
	};

	const entityType = entityTypeList.items[@intFromEnum(entityTypeIndex)];

	for(std.meta.declarations(components), 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 0) {
			continue;
		}

		@field(components, decl.name).deinitData(main.globalAllocator, entityIndex, entityType.index);
	}

	entityIndexToEntityTypeIndex.remove(entityIndex);

	freeList.append(allocator, entityIndex);
}

pub fn deinit() void {
	arenaAllocator.deinit();

	inline for(std.meta.declarations(components)) |decl| {
		@field(components, decl.name).deinit(main.globalAllocator);
	}
}

pub fn reset() void {
	_ = arenaAllocator.reset(.free_all);
}
