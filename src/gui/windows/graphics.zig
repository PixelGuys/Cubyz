const std = @import("std");

const main = @import("root");
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

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;
const renderDistances = [_]u16{4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24};

const anisotropy = [_]u8{1, 2, 4, 8, 16};

const resolutions = [_]u16{25, 50, 100};

fn renderDistanceCallback(newValue: u16) void {
	settings.renderDistance = newValue + renderDistances[0];
}

fn fovCallback(newValue: f32) void {
	settings.fov = newValue;
	main.Window.GLFWCallbacks.framebufferSize(undefined, main.Window.width, main.Window.height);
}

fn fovFormatter(allocator: main.utils.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffField Of View: {d:.0}°", .{value}) catch unreachable;
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

fn anisotropicFilteringCallback(newValue: u16) void {
	settings.anisotropicFiltering = anisotropy[newValue];
	main.blocks.meshes.reloadTextures(undefined);
}

fn resolutionScaleCallback(newValue: u16) void {
	settings.resolutionScale = std.math.pow(f32, 2.0, @as(f32, @floatFromInt(newValue)) - 2.0);
	main.Window.GLFWCallbacks.framebufferSize(null, main.Window.width, main.Window.height);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffRender Distance: ", "{}", &renderDistances, settings.renderDistance - renderDistances[0], &renderDistanceCallback));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 40.0, 120.0, settings.fov, &fovCallback, &fovFormatter));
	list.add(CheckBox.init(.{0, 0}, 128, "Bloom", settings.bloom, &bloomCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Vertical Synchronization", settings.vsync, &vsyncCallback));
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffAnisotropic Filtering: ", "{}x", &anisotropy, switch(settings.anisotropicFiltering) {1 => 0, 2 => 1, 4 => 2, 8 => 3, 16 => 4, else => 2}, &anisotropicFilteringCallback));
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