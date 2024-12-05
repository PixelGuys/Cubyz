const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");
const Label = @import("../components/Label.zig");

pub var window: GuiWindow = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

pub var text: []const u8 = "";

const padding: f32 = 16;
const width: f32 = 256;

fn ack(_: usize) void {
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, text, .center));
	list.add(Button.initText(.{0, 0}, 100, "OK", .{ .callback = &ack }));
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
