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
const DiscreteSlider = @import("../components/DiscreteSlider.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
	.id = "graphics",
};

const padding: f32 = 8;

fn renderDistanceCallback(newValue: u16) void {
	settings.renderDistance = newValue + 1;
}

fn LODFactorCallback(newValue: u16) void {
	settings.LODFactor = @as(f32, @floatFromInt(newValue + 1))/2;
}

fn bloomCallback(newValue: bool) void {
	settings.bloom = newValue;
}

fn vsyncCallback(newValue: bool) void {
	settings.vsync = newValue;
	main.Window.reloadSettings();
}

fn anisotropicFilteringCallback(newValue: bool) void {
	settings.anisotropicFiltering = newValue;
	// TODO: Reload the textures.
}

pub fn onOpen() Allocator.Error!void {
	const list = try VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const renderDistances = [_]u32{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12};
	try list.add(try DiscreteSlider.init(.{0, 0}, 128, "#ffffffRender Distance: ", "{}", &renderDistances, settings.renderDistance - 1, &renderDistanceCallback));
	try list.add(try CheckBox.init(.{0, 0}, 128, "Bloom", settings.bloom, &bloomCallback));
	try list.add(try CheckBox.init(.{0, 0}, 128, "Vertical Synchronization", settings.vsync, &vsyncCallback));
	try list.add(try CheckBox.init(.{0, 0}, 128, "Anisotropic Filtering", settings.anisotropicFiltering, &anisotropicFilteringCallback));
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