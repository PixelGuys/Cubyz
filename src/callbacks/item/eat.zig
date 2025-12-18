const std = @import("std");

const main = @import("main");

energy: f32,

pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.energy = zon.get(f32, "food", 1.0),
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.UseItemCallback.Params) main.callbacks.Result {
	const cmd = params.cmd;
	const allocator = params.allocator;
	const user = params.user;
	const side = params.side;
	const stack = params.source.ref();

	// enough items there?
	if(stack.amount < 1)
		return .ignored;

	const previous = if(side == .server) user.?.player.energy else main.game.Player.super.energy;
	const maxEnergy = if(side == .server) user.?.player.maxEnergy else main.game.Player.super.maxEnergy;
	if(self.energy > 0 and previous >= maxEnergy)
		return .ignored;

	cmd.executeBaseOperation(allocator, .{.addEnergy = .{
		.target = user,
		.energy = self.energy,
		.previous = previous,
	}}, side);

	// Apply inventory changes:
	if(params.gamemode == .creative) return .handled;

	cmd.executeBaseOperation(allocator, .{.delete = .{
		.source = params.source,
		.amount = 1,
	}}, side);
	return .handled;
}
