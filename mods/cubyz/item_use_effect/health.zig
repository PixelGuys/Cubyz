const std = @import("std");

const main = @import("main");
const Inventory = main.items.Inventory;
const ZonElement = main.ZonElement;

amount: f32,

pub fn init(_: main.heap.NeverFailingAllocator, zon: ZonElement) @This() {
	return .{
		.amount = zon.get(f32, "amount", 0),
	};
}
pub fn apply(self: *const @This(), _: *main.game.World) void {
	Inventory.Sync.addHealth(self.amount, .heal, .client, main.game.Player.id);
}
