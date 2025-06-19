const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const VerticalList = GuiComponent.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn reorderHudCallbackFunction(_: usize) void {
	gui.reorderWindows = !gui.reorderWindows;
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	if(main.server.world != null) {
		list.add(Button.initText(.{0, 0}, 128, "Invite Player", gui.openWindowCallback("cubyz:invite")));
	}
	list.add(Button.initText(.{0, 0}, 128, "Settings", gui.openWindowCallback("cubyz:settings")));
	list.add(Button.initText(.{0, 0}, 128, "Reorder HUD", .{.callback = &reorderHudCallbackFunction}));
	list.add(Button.initText(.{0, 0}, 128, "Exit World", .{.callback = &main.exitToMenu}));
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
