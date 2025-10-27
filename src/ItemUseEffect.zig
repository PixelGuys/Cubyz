const std = @import("std");

const blocks = @import("blocks.zig");
const Block = blocks.Block;
const chunk = @import("chunk.zig");
const Neighbor = chunk.Neighbor;
const main = @import("main");
const ModelIndex = main.models.ModelIndex;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const Vec3f = vec.Vec3f;
const Mat4f = vec.Mat4f;
const ZonElement = main.ZonElement;

const list = @import("item_use_effect");

const ItemUseEffect = @This();

const ItemUseEffectInner = blk: {
	var unionFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.UnionField = undefined;
	var enumFields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.EnumField = undefined;
	for(0.., @typeInfo(list).@"struct".decls) |i, declaration| {
		unionFields[i] = std.builtin.Type.UnionField{
			.name = declaration.name,
			.type = *const @field(list, declaration.name),
			.alignment = 0,
		};
		enumFields[i] = std.builtin.Type.EnumField{
			.name = declaration.name,
			.value = i,
		};
	}
	const enum_ = @Type(.{
		.@"enum" = .{
			.fields = &enumFields,
			.decls = &.{},
			.is_exhaustive = false,
			.tag_type = std.meta.Int(.unsigned, std.math.log2_int(usize, unionFields.len) + 1),
		},
	});
	break :blk @Type(.{
		.@"union" = .{
			.fields = &unionFields,
			.decls = &.{},
			.layout = .auto,
			.tag_type = enum_,
		},
	});
};

inner: ItemUseEffectInner,
pub fn createByID(allocator: main.heap.NeverFailingAllocator, id: []const u8, zon: ZonElement) ?ItemUseEffect {
	inline for(@typeInfo(list).@"struct".decls) |decl| {
		if(std.mem.eql(u8, decl.name, id)) {
			const value = allocator.create(@field(list, decl.name));
			value.* = .init(allocator, zon);
			return .{.inner = @unionInit(ItemUseEffectInner, decl.name, value)};
		}
	}
	return null;
}

pub fn parse(allocator: main.heap.NeverFailingAllocator, zon: ZonElement) ?ItemUseEffect {
	const id = zon.get(?[]const u8, "id", null) orelse return null;
	return createByID(allocator, id, zon);
}

pub fn apply(self: *const ItemUseEffect, world: *main.game.World) void {
	switch(self.inner) {
		inline else => |effect| effect.apply(world),
	}
}
