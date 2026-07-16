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
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn reorderHudCallbackFunction() void {
	gui.reorderWindows = !gui.reorderWindows;
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const isSingleplayer = if (main.server.world) |w| w.mode == .singleplayer else false;
	list.add(Button.initText(.{0, 0}, 128, "Players", .{.onAction = gui.openWindowCallback("players"), .disabled = isSingleplayer}));
	if (main.server.world != null) {
		list.add(Button.initText(.{0, 0}, 128, "Invite Player", .{.onAction = gui.openWindowCallback("invite"), .disabled = isSingleplayer}));
	}
	list.add(Button.initText(.{0, 0}, 128, "Settings", .{.onAction = gui.openWindowCallback("settings")}));
	list.add(Button.initText(.{0, 0}, 128, "Reorder HUD", .{.onAction = .init(reorderHudCallbackFunction)}));
	list.add(Button.initText(.{0, 0}, 128, "Exit World", .{.onAction = .init(main.exitToMenu)}));
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
