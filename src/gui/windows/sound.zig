const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

fn musicCallback(newValue: f32) void {
	settings.musicVolume = deziBelToLinear(newValue);
	settings.save();
}

fn deziBelToLinear(x: f32) f32 {
	if(x < -59.95) return 0;
	return std.math.pow(f32, 10, x/20);
}

fn linearToDezibel(x: f32) f32 {
	const db = 20*std.math.log10(x);
	if(db < -59.95) return -60;
	return db;
}

fn musicFormatter(allocator: NeverFailingAllocator, value: f32) []const u8 {
	const percentage = 100*deziBelToLinear(value);
	if(percentage == 0) return allocator.dupe(u8, "Music volume: Off");
	return std.fmt.allocPrint(allocator.allocator, "Music volume:", .{}) catch unreachable;
}

const padding: f32 = 8;

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 128, -60, 0, linearToDezibel(settings.musicVolume), &musicCallback, &musicFormatter));
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
