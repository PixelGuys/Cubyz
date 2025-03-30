const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Graphics", gui.openWindowCallback("graphics")));
	list.add(Button.initText(.{0, 0}, 128, "Sound", gui.openWindowCallback("sound")));
	list.add(Button.initText(.{0, 0}, 128, "Controls", gui.openWindowCallback("controls")));
	list.add(Button.initText(.{0, 0}, 128, "Advanced Controls", gui.openWindowCallback("advanced_controls")));
	list.add(Button.initText(.{0, 0}, 128, "Change Name", gui.openWindowCallback("change_name")));
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
