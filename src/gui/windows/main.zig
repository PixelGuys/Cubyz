const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:main",
	.components = &components,
};

pub fn buttonCallbackTest() void {
	std.log.info("Clicked!", .{});
}

const padding: f32 = 8;

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 16);
	try list.add(try Button.init(.{0, 0}, 128, "Singleplayer TODO", &buttonCallbackTest));
	try list.add(try Button.init(.{0, 0}, 128, "Multiplayer", gui.openWindowFunction("cubyz:multiplayer")));
	try list.add(try Button.init(.{0, 0}, 128, "Settings", gui.openWindowFunction("cubyz:settings")));
	try list.add(try Button.init(.{0, 0}, 128, "Exit TODO", &buttonCallbackTest));
	list.finish(.center);
	components[0] = list.toComponent();
	window.contentSize = components[0].pos() + components[0].size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}