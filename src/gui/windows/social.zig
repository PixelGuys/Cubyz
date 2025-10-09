const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 128},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn streamerModeCallback(enabled: bool) void {
	settings.streamerModeEnabled = enabled;
	settings.save();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 128, 16);
	list.add(CheckBox.init(.{0, 0}, 120, "Enable Streamer Mode (hides sensitive info)", settings.streamerModeEnabled, &streamerModeCallback));
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
