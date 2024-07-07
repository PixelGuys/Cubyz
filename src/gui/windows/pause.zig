const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

fn reorderHudCallbackFunction(_: usize) void {
	gui.reorderWindows = !gui.reorderWindows;
}
fn exitMenuCallbackFunction(_: usize) void {
	if(main.game.world) |world| {
		world.deinit();
		main.game.world = null;
	}
	gui.openWindow("main");
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	if(main.server.world != null) {
		list.add(Button.initText(.{0, 0}, 128, "Invite Player", gui.openWindowCallback("invite")));
	}
	list.add(Button.initText(.{0, 0}, 128, "Settings", gui.openWindowCallback("settings")));
	list.add(Button.initText(.{0, 0}, 128, "Reorder HUD", .{.callback = &reorderHudCallbackFunction}));
	list.add(Button.initText(.{0, 0}, 128, "Exit to Menu TODO", .{
		.callback = &exitMenuCallbackFunction,
	}));
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