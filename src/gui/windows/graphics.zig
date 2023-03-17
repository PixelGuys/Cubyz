const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const Slider = @import("../components/Slider.zig");
const VerticalList = @import("../components/VerticalList.zig");

var components: [1]GuiComponent = undefined;
pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "cubyz:graphics",
	.title = "Graphics",
	.onOpenFn = &onOpen,
	.onCloseFn = &onClose,
	.components = &components,
};

const padding: f32 = 8;

fn renderDistanceCallback(newValue: u16) void {
	settings.renderDistance = newValue + 1;
}

fn LODFactorCallback(newValue: u16) void {
	settings.LODFactor = @intToFloat(f32, newValue + 1)/2;
}

fn bloomCallback(newValue: bool) void {
	settings.bloom = newValue;
}

fn vsyncCallback(newValue: bool) void {
	settings.vsync = newValue;
	main.Window.reloadSettings();
}

pub fn onOpen() Allocator.Error!void {
	var list = try VerticalList.init();
	const renderDistances = [_]u32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
	try list.add(try Slider.init(.{0, 16}, 128, "#ffffffRender Distance: ", "{}", &renderDistances, settings.renderDistance - 1, &renderDistanceCallback));
	const LODFactors = [_]f32{0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6, 6.5, 7, 7.5, 8};
	try list.add(try Slider.init(.{0, 16}, 128, "#ffffffLOD Factor: ", "{d:.1}", &LODFactors, @floatToInt(u16, settings.LODFactor*2) - 1, &LODFactorCallback));
	// TODO: fog?
	try list.add(try CheckBox.init(.{0, 16}, 128, "Bloom", settings.bloom, &bloomCallback));
	try list.add(try CheckBox.init(.{0, 16}, 128, "Vertical Synchronization", settings.vsync, &vsyncCallback));
	components[0] = list.toComponent(.{padding, padding});
	window.contentSize = components[0].size + @splat(2, @as(f32, 2*padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	for(&components) |*comp| {
		comp.deinit();
	}
}