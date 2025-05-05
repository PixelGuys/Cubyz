const std = @import("std");

const main = @import("main");

const ZonElement = main.ZonElement;

const Entity = main.server.Entity;

const componentlist = @import("components/_components.zig");
const systemlist = @import("systems/_systems.zig");

const SparseSet = main.utils.SparseSet;

pub const Components = listToEnum(componentlist);
pub const Systems = listToEnum(systemlist);

pub var components: listToSparseSets(componentlist, u32) = undefined;
pub var systems: SparseSet(SystemBitset, u32) = undefined;

pub var entityTypeComponents: listToSparseSets(componentlist, u16) = undefined;
pub var entityTypeComponentBitset: [main.entity.maxEntityTypeCount]ComponentBitset = undefined;
pub var entityTypeSystemBitset: [main.entity.maxEntityTypeCount]SystemBitset = undefined;

const ComponentBitset = listToBitset(componentlist);
const SystemBitset = listToBitset(systemlist);

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

pub fn addComponent(entityType: u16, comptime component: Components, zon: ZonElement) void {
	const componentType = @field(componentlist, @tagName(component));

	_ = @field(entityTypeComponents, @tagName(component)).add(entityType, componentType.loadFromZon(zon));
	@field(entityTypeComponentBitset[entityType], @tagName(component)) = true;
}

pub fn addSystem(entityType: u16, comptime system: Systems) void {
	@field(entityTypeSystemBitset[entityType], @tagName(system)) = true;
}

pub fn init() void {
	inline for (@typeInfo(@TypeOf(components)).@"struct".fields) |field| {
		std.debug.print("{s}\n", .{field.name});
		@field(components, field.name) = .init(main.globalAllocator);
	}
	
	systems = .init(main.globalAllocator);
}

pub fn deinit() void {
	inline for (@typeInfo(@TypeOf(components)).@"struct".decls) |field| {
		@field(components, field.name).deinit();
	}

	systems.deinit();
}