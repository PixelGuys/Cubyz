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

const list = @import("food_effect");

const FoodEffect = @This();

const FoodEffectInner = blk: {
	var fields: [@typeInfo(list).@"struct".decls.len]std.builtin.Type.UnionField = undefined;
	for(0.., @typeInfo(list).@"struct".decls) |i, declaration| {
		fields[i] = std.builtin.Type.UnionField {
			.name = declaration.name,
			.type =  @field(list, declaration.name),
			.alignment = 0,
		};
	}
	break :blk @Type(.{
		.@"union" = .{
			.fields = &fields,
			.decls = &.{},
			.layout = .auto,
			.tag_type = null,
		}
	});
};

inner: FoodEffectInner,
pub fn createByID(allocator: main.heap.NeverFailingAllocator, id: []const u8, zon: ZonElement) ?FoodEffect {
	inline for(@typeInfo(FoodEffectInner).@"union".fields) |field| {
		if(std.mem.eql(u8, field.name, id)) {
			return .{
				.inner = @unionInit(FoodEffectInner, field.name, @FieldType(FoodEffectInner, field.name).init(allocator, zon))
			};
		}
	}
	return null;
}

pub fn parse(allocator: main.heap.NeverFailingAllocator, zon: ZonElement) ?FoodEffect {
	const id = zon.get(?[]const u8, "id", null) orelse return null;
	return createByID(allocator, id, zon);
}

pub fn apply(self: *FoodEffect, world: *main.game.World, player: *main.game.Player) void {
	switch(self.inner) {
		inline else => |effect| effect.apply(world, player),
	}
}
