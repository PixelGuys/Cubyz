const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const c = @import("c");

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeable = false,
};

const padding: f32 = 8;

fn exitGame() void {
	c.glfwSetWindowShouldClose(main.Window.window, c.GLFW_TRUE);
}
fn singleplayerSelection() void {
	gui.windowlist.save_selection.mode = .singleplayer;
	gui.openWindow("save_selection");
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Singleplayer", .{.onAction = .init(singleplayerSelection)}));
	list.add(Button.initText(.{0, 0}, 128, "Multiplayer", .{.onAction = gui.openWindowCallback("multiplayer")}));
	list.add(Button.initText(.{0, 0}, 128, "Settings", .{.onAction = gui.openWindowCallback("settings")}));
	list.add(Button.initText(.{0, 0}, 128, "Touch Grass", .{.onAction = .init(exitGame)}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
