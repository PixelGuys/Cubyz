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
const renderDistances = [_]u16{5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24};
const lodValues = [_][]const u8{"0.5", "1", "2", "3", "4", "5"};

const anisotropy = [_]u8{1, 2, 4, 8, 16};

const resolutions = [_]u16{25, 50, 100};

const leavesQualities = [_]u8{0, 1, 2, 3, 4};

fn fpsCapRound(newValue: f32) ?u32 {
	if(newValue < 144.0) {
		return @as(u32, @intFromFloat(newValue/5.0))*5;
	} else if(newValue < 149.0) {
		return 144;
	} else {
		return null;
	}
}

fn fpsCapFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	const cap = fpsCapRound(value);
	if(cap == null)
		return allocator.dupe(u8, "#ffffffFPS: Unlimited");
	return std.fmt.allocPrint(allocator.allocator, "#ffffffFPS Limit: {d:.0}", .{cap.?}) catch unreachable;
}

fn fpsCapCallback(newValue: f32) void {
	settings.fpsCap = fpsCapRound(newValue);
	settings.save();
}

fn renderDistanceCallback(newValue: u16) void {
	settings.renderDistance = newValue + renderDistances[0];
	settings.save();
}

fn highestLodCallback(newValue: u16) void {
	settings.highestLod = @intCast(@min(newValue, settings.highestSupportedLod));
	settings.save();
}

fn leavesQualityCallback(newValue: u16) void {
	settings.leavesQuality = newValue;
	settings.save();
}

fn fovCallback(newValue: f32) void {
	settings.fov = newValue;
	settings.save();
}

fn fovFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffField Of View: {d:.0}°", .{value}) catch unreachable;
}

fn lodDistanceFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffOpaque leaves distance: {d:.0}", .{@round(value)}) catch unreachable;
}

fn lodDistanceCallback(newValue: f32) void {
	settings.@"lod0.5Distance" = @round(newValue);
	settings.save();
}

fn contrastFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "#ffffffBlock Contrast: {d:.0}%", .{@round(value*100)}) catch unreachable;
}

fn contrastCallback(newValue: f32) void {
	settings.blockContrast = @round(newValue*100)/100;
	settings.save();
}

fn bloomCallback(newValue: bool) void {
	settings.bloom = newValue;
	settings.save();
}

fn vsyncCallback(newValue: bool) void {
	settings.vsync = newValue;
	settings.save();
	main.Window.reloadSettings();
}

fn anisotropicFilteringCallback(newValue: u16) void {
	settings.anisotropicFiltering = anisotropy[newValue];
	settings.save();
	if(main.game.world != null) {
		main.blocks.meshes.reloadTextures(undefined);
	}
}

fn resolutionScaleCallback(newValue: u16) void {
	settings.resolutionScale = std.math.pow(f32, 2.0, @as(f32, @floatFromInt(newValue)) - 2.0);
	settings.save();
	main.Window.GLFWCallbacks.framebufferSize(null, main.Window.width, main.Window.height);
}

fn vulkanTestingWindowCallback(newValue: bool) void {
	settings.vulkanTestingWindow = newValue;
	settings.save();
	main.Window.reloadSettings();
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(ContinuousSlider.init(.{0, 0}, 128, 10.0, 154.0, @floatFromInt(settings.fpsCap orelse 154), &fpsCapCallback, &fpsCapFormatter));
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffRender Distance: ", "{}", &renderDistances, @min(@max(settings.renderDistance, renderDistances[0]) - renderDistances[0], renderDistances.len - 1), &renderDistanceCallback));
	if(main.game.world == null) {
		list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffHighest LOD: ", "{s}", &lodValues, @min(settings.highestLod, settings.highestSupportedLod), &highestLodCallback));
	}
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffLeaves Quality (TODO: requires reload): ", "{}", &leavesQualities, settings.leavesQuality - leavesQualities[0], &leavesQualityCallback));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 50.0, 400.0, settings.@"lod0.5Distance", &lodDistanceCallback, &lodDistanceFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 0.0, 0.5, settings.blockContrast, &contrastCallback, &contrastFormatter));
	list.add(ContinuousSlider.init(.{0, 0}, 128, 40.0, 120.0, settings.fov, &fovCallback, &fovFormatter));
	list.add(CheckBox.init(.{0, 0}, 128, "Bloom", settings.bloom, &bloomCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Vertical Synchronization", settings.vsync, &vsyncCallback));
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffAnisotropic Filtering: ", "{}x", &anisotropy, switch(settings.anisotropicFiltering) {
		1 => 0,
		2 => 1,
		4 => 2,
		8 => 3,
		16 => 4,
		else => 2,
	}, &anisotropicFilteringCallback));
	list.add(DiscreteSlider.init(.{0, 0}, 128, "#ffffffResolution Scale: ", "{}%", &resolutions, @as(u16, @intFromFloat(@log2(settings.resolutionScale) + 2.0)), &resolutionScaleCallback));
	list.add(CheckBox.init(.{0, 0}, 128, "Vulkan testing window (requires restart)", settings.vulkanTestingWindow, &vulkanTestingWindowCallback));
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
