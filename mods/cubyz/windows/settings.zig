const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const VerticalList = GuiComponent.VerticalList;

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Graphics", gui.openWindowCallback("cubyz:graphics")));
	list.add(Button.initText(.{0, 0}, 128, "Sound", gui.openWindowCallback("cubyz:sound")));
	list.add(Button.initText(.{0, 0}, 128, "Controls", gui.openWindowCallback("cubyz:controls")));
	list.add(Button.initText(.{0, 0}, 128, "Advanced Controls", gui.openWindowCallback("cubyz:advanced_controls")));
	list.add(Button.initText(.{0, 0}, 128, "Change Name", gui.openWindowCallback("cubyz:change_name")));
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
