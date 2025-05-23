const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const DynamicPackedIntArray = main.utils.DynamicPackedIntArray;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const SparseSet = main.utils.SparseSet;
const DenseId = main.utils.DenseId;

const component_list = @import("components/_list.zig");

pub const EntityTypeIndex = DenseId(u16);
pub const EntityIndex = DenseId(u16);

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var allocator: NeverFailingAllocator = undefined;

var freeList: main.ListUnmanaged(EntityIndex) = undefined;

var entityTypeList: main.ListUnmanaged(EntityType) = undefined;
var entityIdToEntityType: std.StringArrayHashMapUnmanaged(EntityTypeIndex) = undefined;
var nextEntityType: u16 = undefined;

var entityIndexToEntityTypeIndex: SparseSet(EntityTypeIndex, EntityIndex) = undefined;

const Component = struct {
	init: *const fn () void,
	deinit: *const fn (allocator: NeverFailingAllocator) void,
	reset: *const fn () void,
	fromZon: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex, zon: ZonElement) void,
	toZon: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex) ZonElement,
	initData: *const fn (allocator: NeverFailingAllocator, entityId: EntityIndex, entityTypeId: EntityTypeIndex) void,
	deinitData: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex) error{ElementNotFound}!void,
	get: *const fn (entityId: EntityIndex) ?*anyopaque,
	initType: *const fn (allocator: NeverFailingAllocator, entityTypeId: EntityTypeIndex, zon: ZonElement) void,
};

const componentList: main.ListUnmanaged(Component) = undefined;
const componentHashMap: std.StringArrayHashMapUnmanaged(u16) = undefined;

const EntityType = struct {
	index: EntityTypeIndex,
	features: main.ListUnmanaged(u16),
};

pub fn init() void {
	arenaAllocator = .init(main.globalAllocator);
	allocator = arenaAllocator.allocator();

	componentList = .{};
	componentHashMap = .{};

	nextEntityType = 0;

	freeList = .initCapacity(allocator, @intFromEnum(EntityIndex.noValue));

	for(0..@intFromEnum(EntityIndex.noValue)) |i| {
		freeList.append(allocator, @enumFromInt(@intFromEnum(EntityIndex.noValue) - i - 1));
	}

	entityTypeList = .{};
	entityIdToEntityType = .{};
	entityIndexToEntityTypeIndex = .{};

	inline for(@typeInfo(component_list).@"struct".decls) |decl| {
		registerComponent(decl.name, @field(component_list, decl.name));
	}

	for (componentList.items) |comp| {
		comp.init();
	}
}

pub fn deinit() void {
	arenaAllocator.deinit();

	for (componentList.items) |comp| {
		comp.deinit(main.globalAllocator);
	}
}

pub fn reset() void {
	_ = arenaAllocator.reset(.free_all);
	
	for (componentList.items) |comp| {
		comp.reset();
	}
}

pub fn registerComponent(id: []const u8, comptime Comp: type) void {
	var result: Component = .{};
	inline for(@typeInfo(result).@"struct".fields) |field| {
		if(@hasDecl(Comp, field.name)) {
			if(field.type == @TypeOf(@field(Comp, field.name))) {
				@field(result, field.name) = @field(Comp, field.name);
			} else {
				@field(result, field.name) = &@field(Comp, field.name);
			}
		}
	}
	componentHashMap.putNoClobber(allocator, id, componentList.items.len);
	componentList.append(allocator, result);
}

pub fn hasRegistered(id: []const u8) bool {
	return entityIdToEntityType.contains(id);
}

pub fn register(_: []const u8, id: []const u8, zon: ZonElement) void {
	const componentMap = zon.getChild("components");

	if(componentMap != .object) {
		std.log.err("components must be an object, not a {s}", .{@tagName(componentMap)});
		return;
	}

	defer nextEntityType += 1;

	var features: main.ListUnmanaged(u16) = .{};

	var iterator = componentMap.object.iterator();
	while(iterator.next()) |entry| {
		const component = entry.key_ptr.*;
		const value = entry.value_ptr.*;

		const componentIndex = componentHashMap.get(component) orelse {
			std.log.err("{s} is not a valid component", .{component});
			continue;
		};

		features.append(main.globalAllocator, componentIndex);

		componentList.items[componentIndex].initType(main.globalAllocator, @enumFromInt(nextEntityType), value);
	}

	entityTypeList.append(allocator, .{
		.index = @enumFromInt(nextEntityType),
		.features = features,
	});
	entityIdToEntityType.put(allocator.allocator, id, @enumFromInt(nextEntityType)) catch unreachable;
}

pub fn getComponent(comptime component: []const u8, entity: EntityIndex) ?*@field(component_list, component).Data {
	return @field(component_list, component).get(entity);
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

	inline for(@typeInfo(component_list).@"struct".decls, 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 1) {
			@field(component_list, decl.name).initData(main.globalAllocator, entityIndex, entityType.index);
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

	inline for(@typeInfo(component_list).@"struct".decls, 0..) |decl, i| {
		if((entityType.features >> i) & 1 == 1) {
			try @field(component_list, decl.name).deinitData(main.globalAllocator, entityIndex, entityType.index);
		}
	}

	try entityIndexToEntityTypeIndex.remove(entityIndex);

	freeList.append(allocator, entityIndex);
}
