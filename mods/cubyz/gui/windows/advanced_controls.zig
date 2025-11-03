const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = gui.Button;
const CheckBox = gui.CheckBox;
const ContinuousSlider = gui.ContinuousSlider;
const DiscreteSlider = gui.DiscreteSlider;
const VerticalList = gui.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;

fn delayCallback(newValue: f32) void {
	settings.updateRepeatDelay = @intFromFloat(newValue);
	settings.save();
}

fn delayFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffPlace/Break Delay: {d:.0} ms", .{value}) catch unreachable;
}

fn speedCallback(newValue: f32) void {
	settings.updateRepeatSpeed = @intFromFloat(newValue);
	settings.save();
}

fn speedFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffPlace/Break Speed: {d:.0} ms", .{value}) catch unreachable;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 128, 1.0, 1000.0, @floatFromInt(settings.updateRepeatDelay), &delayCallback, &delayFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 1.0, 500.0, @floatFromInt(settings.updateRepeatSpeed), &speedCallback, &speedFormatter));
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
