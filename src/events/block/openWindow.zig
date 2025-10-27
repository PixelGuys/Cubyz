const std = @import("std");

const main = @import("main");
const Block = main.blocks.Block;
const vec = main.vec;
const Vec3i = vec.Vec3i;
const ZonElement = main.ZonElement;

windowName: []const u8,

pub fn load(zon: ZonElement) ?*@This() {
	const result = main.worldArena.create(@This());
	result.* = .{
		.windowName = main.worldArena.dupe(u8, zon.get(?[]const u8, "name", null) orelse {
			std.log.err("openWindow event is missing \"name\" field.", .{});
			return null;
		}),
	};
	return result;
}

pub fn run(self: *@This(), _: main.events.BlockEvent.Params) main.events.EventResult {
	main.gui.openWindow(self.windowName);
	main.Window.setMouseGrabbed(false);
	return .handled;
}
