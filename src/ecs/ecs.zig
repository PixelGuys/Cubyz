const std = @import("std");

const main = @import("main");

const componentlist = @import("components/_components.zig");
const systemlist = @import("systems/_systems.zig");

const SparseSet = main.utils.SparseSet;

pub var components: listToSparseSets(componentlist) = undefined;
pub var systems: listToSparseSets(systemlist) = undefined;

const ComponentBitset = listToBitset(componentlist);
const SystemBitset = listToBitset(systemlist);

fn listToSparseSets(comptime list: type) type {
	const outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		const typ = @field(list, name);
		outFields[i] = .{
			.name = name,
			.type = SparseSet(typ, u32),
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = @alignOf(SparseSet(typ, u32)),
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
	const outFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.StructField = undefined;

	for (@typeInfo(list).@"struct".decls, 0..) |decl, i| {
		const name = decl.name;
		outFields[i] = .{
			.name = name,
			.type = bool,
			.default_value_ptr = null,
			.is_comptime = false,
			.alignment = @alignOf(bool),
		};
	}

	return @Type(.{.@"struct" = .{
		.layout = .@"packed",
        .fields = &outFields,
        .decls = &.{},
        .is_tuple = false,
	}});
}

pub fn init() void {
	inline for (@typeInfo(componentlist).@"struct".decls) |decl| {
		@field(components, decl.name) = .init(main.globalAllocator);
	}
}

pub fn deinit() void {
	inline for (@typeInfo(componentlist).@"struct".decls) |decl| {
		@field(components, decl.name).deinit();
	}
}