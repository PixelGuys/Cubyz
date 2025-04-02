const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

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

fn exitGame(_: usize) void {
	main.Window.c.glfwSetWindowShouldClose(main.Window.window, main.Window.c.GLFW_TRUE);
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Singleplayer", gui.openWindowCallback("save_selection")));
	list.add(Button.initText(.{0, 0}, 128, "Multiplayer", gui.openWindowCallback("multiplayer")));
	list.add(Button.initText(.{0, 0}, 128, "Settings", gui.openWindowCallback("settings")));
	list.add(Button.initText(.{0, 0}, 128, "Touch Grass", .{.callback = &exitGame}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
