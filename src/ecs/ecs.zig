const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Entity = main.server.Entity;

const componentlist = @import("components/_components.zig");
const systemList = @import("systems/_systems.zig");

const SparseSet = main.utils.SparseSet;

pub const Components = listToEnum(componentlist);
pub const Systems = listToEnum(systemList);

pub var componentStorage: listToSparseSets(componentlist, u16) = undefined;

pub var componentDefaultStorage: listToSparseSets(componentlist, u16) = undefined;
pub var componentBitsetStorage: [main.entity.maxEntityTypeCount]ComponentBitset = undefined;
pub var systemBitsetStorage: [main.entity.maxEntityTypeCount]SystemBitset = undefined;

const ComponentBitset = listToBitset(componentlist);
const SystemBitset = listToBitset(systemList);

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

pub fn addComponent(entityType: u16, comptime component: Components, zon: ZonElement) void {
	const componentType = @field(componentlist, @tagName(component));

	_ = @field(componentDefaultStorage, @tagName(component)).add(entityType, componentType.loadFromZon(zon));
	@field(componentBitsetStorage[entityType], @tagName(component)) = true;
}

pub fn addSystem(entityType: u16, comptime system: Systems) void {
	@field(systemBitsetStorage[entityType], @tagName(system)) = true;
}

pub fn init() void {
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".fields) |field| {
		std.debug.print("{s}\n", .{field.name});
		@field(componentStorage, field.name) = .init(main.globalAllocator);
	}
}

pub fn deinit() void {
	inline for (@typeInfo(@TypeOf(componentStorage)).@"struct".decls) |field| {
		@field(componentStorage, field.name).deinit();
	}
}