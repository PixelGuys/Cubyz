const std = @import("std");

const main = @import("main");

pub const Data = packed struct(u128) { strength: f32, pad: u96 = undefined };

pub const priority = 1;

pub fn loadData(zon: main.ZonElement) Data {
	return .{.strength = @max(0, zon.get(f32, "strength", 0))};
}

pub fn combineModifiers(data1: Data, data2: Data) ?Data {
	return .{.strength = std.math.hypot(data1.strength, data2.strength)};
}

pub fn onBlockUpdate(blockUpdate: main.sync.Command.UpdateBlock, ctx: main.sync.Command.Context, shouldDropSourceBlockOnSuccess: *bool, data: Data) void {
	if (ctx.gamemode != .survival) return;
	if (blockUpdate.oldBlock.typ == blockUpdate.newBlock.typ) return;

	ctx.execute(.{.addHealth = .{
		.target = ctx.user,
		.health = data.strength*blockUpdate.oldBlock.blockHealth()*blockUpdate.oldBlock.blockResistance()*0.1,
		.cause = .modifier,
		.previous = if (ctx.side == .server) ctx.user.?.player().health else main.game.Player.super.health,
	}});
	shouldDropSourceBlockOnSuccess.* = false;

	return;
}

pub fn printTooltip(outString: *main.List(u8), data: Data) void {
	outString.print("#f84a00**Devouring**#808080 *Consume block drops to heal player for {d:.1}% of block health and resistance.**", .{data.strength*100});
}
