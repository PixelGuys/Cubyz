const std = @import("std");

const main = @import("main");
const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const VerticalList = GuiComponent.VerticalList;
const Vec2f = main.vec.Vec2f;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

fn multiplayerSelection() void {
	gui.windows.@"cubyz:save_selection".mode = .multiplayer;
	gui.closeWindow("cubyz:save_selection");
	gui.openWindow("cubyz:save_selection");
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Host World", .{.onAction = .init(multiplayerSelection)}));
	list.add(Button.initText(.{0, 0}, 128, "Join Server", .{.onAction = gui.openWindowCallback("cubyz:multiplayer_join")}));
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
