const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Entity = main.server.Entity;

const componentlist = @import("components/_components.zig");
const systemList = @import("systems/_systems.zig");

const SparseSet = main.utils.SparseSet;

pub const Components = listToEnum(componentlist);
pub const Systems = listToEnum(systemList);

const ComponentBitset = listToBitset(componentlist);
const SystemBitset = listToBitset(systemList);
const ComponentIds = listToIds(componentlist);

var ecsArena: main.heap.NeverFailingArenaAllocator = .init(main.globalAllocator);
var ecsAllocator: main.heap.NeverFailingAllocator = ecsArena.allocator();

var entityTypes: SparseSet(u16, u16) = undefined;

var componentStorage: listToSparseSets(componentlist, u16) = undefined;
var componentIdStorage: SparseSet(ComponentIds, u16) = undefined;

var componentDefaultStorage: listToSparseSets(componentlist, u16) = undefined;
var componentBitsetStorage: [main.entity.maxEntityTypeCount]ComponentBitset = undefined;
var systemBitsetStorage: [main.entity.maxEntityTypeCount]SystemBitset = undefined;

fn listToSparseSets(comptime list: type, comptime idType: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		const typ = @field(list, name);
		outFields[i] = .{
			.name = name,
			.type = SparseSet(typ, idType),
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = @alignOf(SparseSet(typ, idType)),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .auto,
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

fn listToIds(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = u16,
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = @alignOf(u16),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .auto,
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

fn listToBitset(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = bool,
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = 0,
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .@"packed",
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

fn listToEnum(comptime list: type) type {
	var outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.EnumField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.value = i,
		};
	}

	return @Type(.{.@"enum" = .{
		.tag_type = u8,
        .fields = &outFields,
        .decls = &.{},
        .is_exhaustive = true,
	}});
}

pub const EntityTypeIndex = struct {
	index: u16,
};

pub const EntityIndex = struct {
	index: u16,
};

pub fn addComponent(entityType: u16, assetFolder: []const u8, id: []const u8, comptime component: Components, zon: ZonElement) void {
	const componentType = @field(componentlist, @tagName(component));

	_ = @field(componentDefaultStorage, @tagName(component)).add(entityType, componentType.loadFromZon(assetFolder, id, zon));
	@field(componentBitsetStorage[entityType], @tagName(component)) = true;
}

pub fn addSystem(entityType: u16, comptime system: Systems) void {
	@field(systemBitsetStorage[entityType], @tagName(system)) = true;
}

pub fn addEntity(entityType: u16) u32 {
	var ids: ComponentIds = undefined;
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		var default = @field(componentDefaultStorage, field.name);
		const id = @field(componentStorage, field.name).add(default.copy());
		@field(ids, field.name) = id;
	}

	entityTypes.add(entityType);
}

pub fn init() void {
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		@field(componentStorage, field.name) = .init(ecsAllocator);
	}

	inline for (@typeInfo(@TypeOf(componentDefaultStorage)).@"struct".fields) |field| {
		@field(componentDefaultStorage, field.name) = .init(ecsAllocator);
	}

	componentIdStorage = .init(ecsAllocator);
	entityTypes = .init(ecsAllocator);
}

pub fn deinit() void {
	ecsArena.deinit();
}

pub fn finalize() void {
	inline for (@typeInfo(@TypeOf(componentDefaultStorage)).@"struct".fields) |field| {
		if (@hasField(@field(componentlist, field.name), "finalize")) {
			@field(componentlist, field.name).finalize();
		}
	}
}