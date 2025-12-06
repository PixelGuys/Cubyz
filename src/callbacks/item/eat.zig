const std = @import("std");

const main = @import("main");

food: f32,
pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.food = zon.get(f32, "food", 1.0),
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.UseItemCallback.Params) main.callbacks.Result {
	const cmd = params.cmd;
	const allocator = params.allocator;
	const user = params.user;
	const side = params.side;
	const gamemode = params.gamemode;
	const source = params.source;
	const stack = params.stack;

	// enough items there?
	if(stack.amount < 1)
		return .ignored;

	const previous = if(side == .server) user.?.player.health else main.game.Player.super.health;
	const maxHealth = if(side == .server) user.?.player.maxHealth else main.game.Player.super.maxHealth;
	if(self.food > 0 and previous >= maxHealth)
		return .ignored;

	cmd.executeBaseOperation(allocator, .{.addHealth = .{
		.target = user,
		.health = self.food,
		.cause = .heal,
		.previous = previous,
	}}, side);

	// Apply inventory changes:
	if(gamemode == .creative) return .handled;

	cmd.executeBaseOperation(allocator, .{.delete = .{
		.source = source,
		.amount = 1,
	}}, side);
	return .handled;
}
