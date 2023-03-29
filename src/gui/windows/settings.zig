const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window: GuiWindow = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:settings",
	.title = "Settings",
};

const padding: f32 = 8;

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 16);
	try list.add(try Button.init(.{0, 0}, 128, "Graphics", gui.openWindowFunction("cubyz:graphics")));
	try list.add(try Button.init(.{0, 0}, 128, "Sound", gui.openWindowFunction("cubyz:sound")));
	try list.add(try Button.init(.{0, 0}, 128, "Controls", gui.openWindowFunction("cubyz:controls")));
	try list.add(try Button.init(.{0, 0}, 128, "Change Name", gui.openWindowFunction("cubyz:change_name")));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}