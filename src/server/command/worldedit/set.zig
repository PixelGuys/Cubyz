const std = @import("std");

const main = @import("main");
const User = main.server.User;
const Pattern = @import("Pattern.zig");

const Block = main.blocks.Block;
const Blueprint = main.blueprint.Blueprint;

pub const description = "Set all blocks within selection to a block.";
pub const usage = "/set <pattern>";

pub fn execute(args: []const u8, source: *User) void {
	if(args.len == 0) {
		source.sendMessage("#ff0000Missing required <pattern> argument.", .{});
		return;
	}
	const pos1 = source.worldEditData.selectionPosition1 orelse {
		return source.sendMessage("#ff0000Position 1 isn't set", .{});
	};
	const pos2 = source.worldEditData.selectionPosition2 orelse {
		return source.sendMessage("#ff0000Position 2 isn't set", .{});
	};
	const pattern = Pattern.initFromString(main.stackAllocator, args) catch |err| {
		source.sendMessage("#ff0000Error parsing pattern: {}", .{err});
		return;
	};
	defer pattern.deinit(main.stackAllocator);

	const maskNullable = source.worldEditData.mask;

	const startX = @min(pos1[0], pos2[0]);
	const startY = @min(pos1[1], pos2[1]);
	const startZ = @min(pos1[2], pos2[2]);

	const width = @abs(pos2[0] - pos1[0]) + 1;
	const depth = @abs(pos2[1] - pos1[1]) + 1;
	const height = @abs(pos2[2] - pos1[2]) + 1;

	for(0..width) |x| {
		const worldX = startX +% @as(i32, @intCast(x));

		for(0..depth) |y| {
			const worldY = startY +% @as(i32, @intCast(y));

			for(0..height) |z| {
				const worldZ = startZ +% @as(i32, @intCast(z));

				if(maskNullable) |mask| {
					const block = main.server.world.?.getBlock(worldX, worldY, worldZ) orelse continue;
					if(mask.match(block)) continue;
				}

				_ = main.server.world.?.updateBlock(worldX, worldY, worldZ, pattern.blocks.sample(&main.seed).block);
			}
		}
	}
}
