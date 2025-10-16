const std = @import("std");

const main = @import("main");
const builtin = @import("builtin");
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
const TextInput = @import("../components/TextInput.zig");
const Label = @import("../components/Label.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

var developerAutoEnterWorldInput: *TextInput = undefined;

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

fn developerGPUInfiniteLoopDetectionCallback(newValue: bool) void {
	main.settings.developerGPUInfiniteLoopDetection = newValue;
	main.settings.save();
}

fn developerAutoEnterWorldCallback(_: usize) void {
	main.globalAllocator.free(main.settings.developerAutoEnterWorld);
	main.settings.developerAutoEnterWorld = main.globalAllocator.dupe(u8, developerAutoEnterWorldInput.currentString.items);
	main.settings.save();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 256, 1.0, 1000.0, @floatFromInt(settings.updateRepeatDelay), &delayCallback, &delayFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 256, 1.0, 500.0, @floatFromInt(settings.updateRepeatSpeed), &speedCallback, &speedFormatter));
	if(builtin.mode == .Debug) {
		list.add(CheckBox.init(.{0, 0}, 256, "GPU Infinite loop detection", main.settings.developerGPUInfiniteLoopDetection, &developerGPUInfiniteLoopDetectionCallback));

		list.add(Label.init(.{0, 0}, 256, "Auto enter world", .left));
		developerAutoEnterWorldInput = TextInput.init(.{0, 0}, 256, 22, main.settings.developerAutoEnterWorld, .{.callback = &developerAutoEnterWorldCallback}, .{});
		list.add(developerAutoEnterWorldInput);
	}

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
