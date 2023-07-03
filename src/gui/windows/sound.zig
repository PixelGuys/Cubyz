const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "sound",
};

fn musicCallback(newValue: f32) void {
	settings.musicVolume = deziBelToLinear(newValue);
}

fn deziBelToLinear(x: f32) f32 {
	if(x < -59.95) return 0;
	return std.math.pow(f32, 10, x/20);
}

fn linearToDezibel(x: f32) f32 {
	const db = 20*std.math.log10(x);
	if(db < -59.95) return -60;
	return 0;
}

fn musicFormatter(allocator: Allocator, value: f32) Allocator.Error![]const u8 {
	const percentage = 100*deziBelToLinear(value);
	if(percentage == 0) return try allocator.dupe(u8, "Music volume: Off");
	return try std.fmt.allocPrint(allocator, "Music volume: {d:.1} dB ({d:.1}%)", .{value, percentage});
}

const padding: f32 = 8;

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init(.{padding, 16 + padding}, 300, 16);
	try list.add(try ContinuousSlider.init(.{0, 0}, 128, -60, 0, linearToDezibel(settings.musicVolume), &musicCallback, &musicFormatter));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @splat(2, @as(f32, padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}