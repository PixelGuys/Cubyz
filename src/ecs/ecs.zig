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

const FeatureMask = @Type(.{.int = .{.bits = @typeInfo(components).@"struct".decls.len, .signedness = .unsigned}});

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var allocator: NeverFailingAllocator = undefined;

var freeList: main.ListUnmanaged(EntityIndex) = undefined;

var entityTypeList: main.ListUnmanaged(EntityType) = undefined;
var entityIdToEntityType: std.StringArrayHashMapUnmanaged(EntityTypeIndex) = undefined;
var nextEntityType: u16 = undefined;

var entityIndexToEntityTypeIndex: SparseSet(EntityTypeIndex, EntityIndex) = undefined;

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

	inline for(@typeInfo(components).@"struct".decls) |decl| {
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
	entityIdToEntityType.put(allocator, id, @enumFromInt(nextEntityType));
}

pub fn getComponent(comptime component: []const u8, entity: EntityIndex) ?*@field(components, component).Data {
	return @field(components, component).get(entity);
}

pub fn getTypeById(id: []const u8) !EntityType {
	const typeIndex = entityIdToEntityType.get(id) orelse {
		std.log.err("Couldn't find entity with id {s}, replacing with noValue", .{id});
		return error.InvalidEntity;
	};
	return entityTypeList.items[@intFromEnum(typeIndex)];
}

pub fn createEntity(id: []const u8) !EntityIndex {
	const entityIndex = freeList.popOrNull() orelse {
		return error.EntityPoolExhausted;
	};

	const entityTypeIndex = entityIdToEntityType.get(id) orelse {
		return error.InvalidEntityType;
	};

	const entityType = entityTypeList.items[@intFromEnum(entityTypeIndex)];

	inline for(@typeInfo(components).@"struct".decls, 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 1) {
			@field(components, decl.name).initData(main.globalAllocator, entityIndex, entityType.index);
		}
	}

	entityIndexToEntityTypeIndex.set(allocator, entityIndex, entityType.index);

	return entityIndex;
}

pub fn removeEntity(entityIndex: EntityIndex) !void {
	const entityTypeIndex = entityIndexToEntityTypeIndex.get(entityIndex) orelse {
		return error.InvalidEntityType;
	};

	const entityType = entityTypeList.items[@intFromEnum(entityTypeIndex.*)];

	inline for(@typeInfo(components).@"struct".decls, 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 1) {
			try @field(components, decl.name).deinitData(main.globalAllocator, entityIndex, entityType.index);
		}
	}

	try entityIndexToEntityTypeIndex.remove(entityIndex);

	freeList.append(allocator, entityIndex);
}

pub fn deinit() void {
	arenaAllocator.deinit();

	inline for(@typeInfo(components).@"struct".decls) |decl| {
		@field(components, decl.name).deinit(main.globalAllocator);
	}
}

pub fn reset() void {
	_ = arenaAllocator.reset(.free_all);
}
