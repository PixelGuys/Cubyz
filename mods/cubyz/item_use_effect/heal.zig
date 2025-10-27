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
pub fn apply(self: *const @This(), side: main.utils.Side, _: *main.game.World) void {
	if(side == .server) {
		Inventory.Sync.addHealth(self.amount, .heal, side, main.game.Player.id);
	}
}
