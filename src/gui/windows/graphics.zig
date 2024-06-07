const std = @import("std");

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
};

const padding: f32 = 8;
const renderDistances = [_]u16{4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24};

const resolutions = [_]u16{25, 50, 100};

fn renderDistanceCallback(newValue: u16) void {
	settings.renderDistance = newValue + renderDistances[0];
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

fn resolutionScaleCallback(newValue: u16) void {
	settings.resolutionScale = std.math.pow(f32, 2.0, @as(f32, @floatFromInt(newValue)) - 2.0);
	main.Window.GLFWCallbacks.framebufferSize(null, main.Window.width, main.Window.height);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffRender Distance: ", "{}", &renderDistances, settings.renderDistance - renderDistances[0], &renderDistanceCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Bloom", settings.bloom, &bloomCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Vertical Synchronization", settings.vsync, &vsyncCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Anisotropic Filtering", settings.anisotropicFiltering, &anisotropicFilteringCallback));
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffResolution Scale: ", "{}%", &resolutions, @as(u16, @intFromFloat(@log2(settings.resolutionScale) + 2.0)), &resolutionScaleCallback));
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