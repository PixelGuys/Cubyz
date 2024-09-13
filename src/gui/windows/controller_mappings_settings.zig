const std = @import("std");

const main = @import("root");
const files = main.files;
const download_controller_mappings = @import("download_controller_mappings.zig");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{256, 256},
	.closeable = false
};

const padding: f32 = 8;

fn askCallback(value: bool) void {
	settings.askToDownloadControllerMappings = !value;
}
fn unrecognizedCallback(value: bool) void {
	settings.downloadControllerMappingsWhenUnrecognized = value;
}
fn periodicCallback(value: bool) void {
	settings.downloadControllerMappings = value;
}
fn onSave(_: usize) void {
	settings.save();
	gui.closeWindowFromRef(&window);
	gui.openWindow("download_controller_mappings");
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, 256, "Controller Mapping Settings", .center));
	list.add(CheckBox.init(.{0, 0}, 256, "Don't ask at startup", !settings.askToDownloadControllerMappings, &askCallback));
	list.add(CheckBox.init(.{0, 0}, 256, "Download controller mappings periodically", settings.downloadControllerMappings, &periodicCallback));
	list.add(CheckBox.init(.{0, 0}, 256, "Download controller mappings when unrecognized controller plugged in", settings.downloadControllerMappingsWhenUnrecognized, &unrecognizedCallback));
	list.add(Button.initText(.{0, 0}, 256, "Save and Close", .{.callback = &onSave}));
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
