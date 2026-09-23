const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn mtuCallBack(newValue: f32) void {
	main.settings.mtu = @round(newValue);
	main.settings.save();
}

fn mtuFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return allocator.print("#ffffffmtu: {d:.0}", .{@round(value)*5});
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Graphics", .{.onAction = gui.openWindowCallback("graphics")}));
	list.add(Button.initText(.{0, 0}, 128, "Audio", .{.onAction = gui.openWindowCallback("audio")}));
	list.add(Button.initText(.{0, 0}, 128, "Controls", .{.onAction = gui.openWindowCallback("controls")}));
	list.add(Button.initText(.{0, 0}, 128, "Advanced Controls", .{.onAction = gui.openWindowCallback("advanced_controls")}));
	list.add(Button.initText(.{0, 0}, 128, "Social", .{.onAction = gui.openWindowCallback("social")}));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 50.0, 400.0, main.settings.mtu, &mtuCallBack, &mtuFormatter));
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
