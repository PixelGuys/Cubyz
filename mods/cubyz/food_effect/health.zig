const std = @import("std");

const main = @import("main");
const Inventory = main.items.Inventory;
const ZonElement = main.ZonElement;

amount: f32,

pub fn init(zon: ZonElement) @This() {
	return .{
		.amount = zon.get(f32, "amount", 0),
	};
}
pub fn apply(self: *@This(), _: *main.game.World, player: *main.game.Player) void {
	Inventory.Sync.addHealth(self.amount, .heal, .client, player.id);
}
pub fn deinit(_: *@This()) void {}
