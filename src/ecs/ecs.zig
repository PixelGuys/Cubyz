const std = @import("std");

const main = @import("main");
const ZonElement = main.ZonElement;
const DynamicPackedIntArray = main.utils.DynamicPackedIntArray;
const NeverFailingArenaAllocator = main.heap.NeverFailingArenaAllocator;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const SparseSet = main.utils.SparseSet;
const DenseId = main.utils.DenseId;

pub const component_list = @import("components/_list.zig");

pub const EntityTypeIndex = DenseId(u16);
pub const EntityIndex = DenseId(u16);

var arenaAllocator: NeverFailingArenaAllocator = undefined;
var allocator: NeverFailingAllocator = undefined;

var freeList: main.ListUnmanaged(EntityIndex) = undefined;

var entityIdToEntityType: std.StringArrayHashMapUnmanaged(EntityTypeIndex) = undefined;
var nextEntityType: u16 = undefined;

var entityIndexToEntityTypeIndex: SparseSet(EntityTypeIndex, EntityIndex) = undefined;

const Component = struct {
	init: *const fn () void,
	deinit: *const fn (allocator: NeverFailingAllocator) void,
	reset: *const fn () void,
	fromZon: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex, zon: ZonElement) void,
	toZon: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex) ZonElement,
	initData: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex) void,
	deinitData: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, entityTypeIndex: EntityTypeIndex) error{ElementNotFound}!void,
	set: *const fn (allocator: NeverFailingAllocator, entityIndex: EntityIndex, dataOpaque: *anyopaque) void,
	get: *const fn (entityIndex: EntityIndex) ?*anyopaque,
	initType: *const fn (allocator: NeverFailingAllocator, entityTypeIndex: EntityTypeIndex, zon: ZonElement) void,
	hasType: *const fn (entityTypeIndex: EntityTypeIndex) bool,
};

var componentList: main.ListUnmanaged(Component) = undefined;
var componentHashMap: std.StringArrayHashMapUnmanaged(u16) = undefined;

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
	for (componentList.items) |comp| {
		comp.deinit(main.globalAllocator);
	}

	arenaAllocator.deinit();
}

pub fn reset() void {
	for (componentList.items) |comp| {
		comp.reset();
	}
	
	_ = arenaAllocator.reset(.free_all);
}

pub fn registerComponent(id: []const u8, comptime Comp: type) void {
	var result: Component = undefined;
	inline for(@typeInfo(Component).@"struct".fields) |field| {
		if(@hasDecl(Comp, field.name)) {
			if(field.type == @TypeOf(@field(Comp, field.name))) {
				@field(result, field.name) = @field(Comp, field.name);
			} else {
				@field(result, field.name) = &@field(Comp, field.name);
			}
		} else unreachable;
	}
	componentHashMap.putNoClobber(allocator.allocator, id, @intCast(componentList.items.len)) catch unreachable;
	componentList.append(allocator, result);
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

	entityIdToEntityType.put(allocator.allocator, id, @enumFromInt(nextEntityType)) catch unreachable;
}

pub fn getComponent(comptime ComponentType: type, component: []const u8, entity: EntityIndex) ?ComponentType.Data {
	const componentIndex = componentHashMap.get(component) orelse {
		std.log.err("Component {s} does not exist", .{component});
		return null;
	};

	const comp = componentList.items[componentIndex];
	const compPtr: *ComponentType.Data = @ptrCast(@alignCast(comp.get(entity) orelse return null));
	return compPtr.*;
}

pub fn setComponent(comptime ComponentType: type, component: []const u8, entity: EntityIndex, data: ComponentType.Data) void {
	const componentIndex = componentHashMap.get(component) orelse {
		std.log.err("Component {s} does not exist", .{component});
		return;
	};

	const comp = componentList.items[componentIndex];

	var dataVar = data;
	comp.set(main.globalAllocator, entity, @ptrCast(&dataVar));
}

pub fn createEntity(id: []const u8) !EntityIndex {
	const entityIndex = freeList.popOrNull() orelse {
		return error.EntityPoolExhausted;
	};

	const entityTypeIndex = entityIdToEntityType.get(id) orelse {
		return error.InvalidEntityType;
	};

	for(componentList.items) |comp| {
		if(comp.hasType(entityTypeIndex)) {
			comp.initData(main.globalAllocator, entityIndex, entityTypeIndex);
		}
	}

	entityIndexToEntityTypeIndex.set(allocator, entityIndex, entityTypeIndex);

	return entityIndex;
}

pub fn removeEntity(entityIndex: EntityIndex) !void {
	const entityTypeIndexPtr = entityIndexToEntityTypeIndex.get(entityIndex) orelse {
		return error.InvalidEntityType;
	};

	const entityTypeIndex = entityTypeIndexPtr.*;

	for(componentList.items) |comp| {
		if(comp.hasType(entityTypeIndex)) {
			try comp.deinitData(main.globalAllocator, entityIndex, entityTypeIndex);
		}
	}

	try entityIndexToEntityTypeIndex.remove(entityIndex);

	freeList.append(allocator, entityIndex);
}
