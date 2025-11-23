const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");
const DiscreteSlider = @import("../components/DiscreteSlider.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn delayCallback(newValue: f32) void {
	settings.updateRepeatDelay.nanoseconds = @intFromFloat(newValue);
	settings.save();
}

fn delayFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffPlace/Break Delay: {d:.0} ms", .{value/1.0e6}) catch unreachable;
}

fn speedCallback(newValue: f32) void {
	settings.updateRepeatSpeed.nanoseconds = @intFromFloat(newValue);
	settings.save();
}

fn speedFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffPlace/Break Speed: {d:.0} ms", .{value/1.0e6}) catch unreachable;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 128, 1.0e6, 1.0e9, @floatFromInt(settings.updateRepeatDelay.nanoseconds), &delayCallback, &delayFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 1.0e6, 0.5e9, @floatFromInt(settings.updateRepeatSpeed.nanoseconds), &speedCallback, &speedFormatter));
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
