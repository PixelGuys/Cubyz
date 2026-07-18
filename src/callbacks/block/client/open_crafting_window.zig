const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

craftingTags: []main.Tag,

pub fn init(zon: ZonElement, _: main.callbacks.Creator) ?*@This() {
	const result = main.worldArena.create(@This());
	const craftingTags = main.Tag.loadTagsFromZon(main.worldArena, zon.getChild("craftingTags"));
	if (craftingTags.len == 0) std.log.err("Error: Missing craftingTags \"name\" for open_crafting_window event.", .{});
	result.* = .{
		.craftingTags = craftingTags,
	};
	return result;
}

pub fn run(self: *@This(), _: main.callbacks.ClientBlockCallback.Params) main.callbacks.Result {
	main.gui.windowlist.inventory_crafting.openFromCallback(self.craftingTags);
	main.Window.setMouseGrabbed(false);
	return .handled;
}
