const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;
var selectedKey: ?*main.Window.Key = null;
var needsUpdate: bool = false;

fn function(keyPtr: usize) void {
	main.Window.setNextKeypressListener(&keypressListener) catch return;
	selectedKey = @ptrFromInt(keyPtr);
	needsUpdate = true;
}

fn keypressListener(key: c_int, mouseButton: c_int, scancode: c_int) void {
	selectedKey.?.key = key;
	selectedKey.?.mouseButton = mouseButton;
	selectedKey.?.scancode = scancode;
	selectedKey = null;
	needsUpdate = true;
	main.settings.save();
}

fn updateSensitivity(sensitivity: f32) void {
	main.settings.mouseSensitivity = sensitivity;
	main.settings.save();
}

fn sensitivityFormatter(allocator: main.utils.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "Mouse Sensitivity: {d:.0}%", .{value*100}) catch unreachable;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 8);
	list.add(ContinuousSlider.init(.{0, 0}, 256, 0, 5, main.settings.mouseSensitivity, &updateSensitivity, &sensitivityFormatter));
	for(&main.KeyBoard.keys) |*key| {
		const label = Label.init(.{0, 0}, 128, key.name, .left);
		const button = if(key == selectedKey) (
			Button.initText(.{16, 0}, 128, "...", .{})
		) else (
			Button.initText(.{16, 0}, 128, key.getName(), .{.callback = &function, .arg = @intFromPtr(key)})
		);
		const row = HorizontalList.init();
		row.add(label);
		row.add(button);
		row.finish(.{0, 0}, .center);
		list.add(row);
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

pub fn render() void {
	if(needsUpdate) {
		needsUpdate = false;
		const oldScroll = window.rootComponent.?.verticalList.scrollBar.currentState;
		onClose();
		onOpen();
		window.rootComponent.?.verticalList.scrollBar.currentState = oldScroll;
	}
}