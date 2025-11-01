const std = @import("std");

const main = @import("main");

dps: f32,
damageType: main.game.DamageType,

pub fn init(zon: main.ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.dps = zon.get(?f32, "dps", null) orelse {
			std.log.err("Missing field \"dps\" for hurt event", .{});
			return null;
		},
		.damageType = std.meta.stringToEnum(main.game.DamageType, zon.get(?[]const u8, "damageType", null) orelse {
			std.log.err("Missing field \"damageType\" for hurt event", .{});
			return null;
		}) orelse {
			std.log.err("Unknown damage type for hurt event", .{});
			return null;
		},
	};
	return result;
}

pub fn run(self: *@This(), params: main.callbacks.BlockTouchCallback.Params) main.callbacks.Result {
	std.debug.assert(params.entity == &main.game.Player.super); // TODO: Implement on the server side
	const damage = self.dps*@as(f32, @floatCast(params.deltaTime));
	main.items.Inventory.Sync.addHealth(-damage, self.damageType, .client, main.game.Player.id);
	return .handled;
}
