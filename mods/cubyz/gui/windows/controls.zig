const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const c = main.Window.c;
const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const ContinuousSlider = @import("../components/ContinuousSlider.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 192},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;
var selectedKey: ?*main.Window.Key = null;
var editingKeyboard: bool = true;
var needsUpdate: bool = false;
fn keyFunction(keyPtr: usize) void {
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

fn gamepadFunction(keyPtr: usize) void {
	main.Window.setNextGamepadListener(&gamepadListener) catch return;
	selectedKey = @ptrFromInt(keyPtr);
	needsUpdate = true;
}
fn gamepadListener(axis: ?main.Window.GamepadAxis, btn: c_int) void {
	selectedKey.?.gamepadAxis = axis;
	selectedKey.?.gamepadButton = btn;
	selectedKey = null;
	needsUpdate = true;
	main.settings.save();
}
fn updateSensitivity(sensitivity: f32) void {
	if(editingKeyboard) {
		main.settings.mouseSensitivity = sensitivity;
	} else {
		main.settings.controllerSensitivity = sensitivity;
	}
	main.settings.save();
}

fn invertMouseYCallback(newValue: bool) void {
	main.settings.invertMouseY = newValue;
	main.settings.save();
}
fn sprintIsToggleCallback(newValue: bool) void {
	main.KeyBoard.setIsToggling("sprint", newValue);
	main.settings.save();
}

fn updateDeadzone(deadzone: f32) void {
	main.settings.controllerAxisDeadzone = deadzone;
}

fn deadzoneFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "Deadzone: {d:.0}%", .{value*100}) catch unreachable;
}

fn sensitivityFormatter(allocator: main.heap.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "{s} Sensitivity: {d:.0}%", .{if(editingKeyboard) "Mouse" else "Controller", value*100}) catch unreachable;
}

fn toggleKeyboard(_: usize) void {
	editingKeyboard = !editingKeyboard;
	needsUpdate = true;
}
fn unbindKey(keyPtr: usize) void {
	var key: ?*main.Window.Key = @ptrFromInt(keyPtr);
	if(editingKeyboard) {
		key.?.key = c.GLFW_KEY_UNKNOWN;
		key.?.mouseButton = -1;
		key.?.scancode = 0;
	} else {
		key.?.gamepadAxis = null;
		key.?.gamepadButton = -1;
	}
	needsUpdate = true;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 364, 8);
	list.add(Button.initText(.{0, 0}, 128, if(editingKeyboard) "Gamepad" else "Keyboard", .{.callback = &toggleKeyboard}));
	list.add(ContinuousSlider.init(.{0, 0}, 256, 0, 5, if(editingKeyboard) main.settings.mouseSensitivity else main.settings.controllerSensitivity, &updateSensitivity, &sensitivityFormatter));
	list.add(CheckBox.init(.{0, 0}, 256, "Invert mouse Y", main.settings.invertMouseY, &invertMouseYCallback));
	list.add(CheckBox.init(.{0, 0}, 256, "Toggle sprint", main.KeyBoard.key("sprint").isToggling == .yes, &sprintIsToggleCallback));

	if(!editingKeyboard) {
		list.add(ContinuousSlider.init(.{0, 0}, 256, 0, 5, main.settings.controllerAxisDeadzone, &updateDeadzone, &deadzoneFormatter));
	}
	for(&main.KeyBoard.keys) |*key| {
		const label = Label.init(.{0, 0}, 128, key.name, .left);
		const button = if(key == selectedKey) (Button.initText(.{16, 0}, 128, "...", .{})) else (Button.initText(.{16, 0}, 128, if(editingKeyboard) key.getName() else key.getGamepadName(), .{.callback = if(editingKeyboard) &keyFunction else &gamepadFunction, .arg = @intFromPtr(key)}));
		const unbindBtn = Button.initText(.{16, 0}, 64, "Unbind", .{.callback = &unbindKey, .arg = @intFromPtr(key)});
		const row = HorizontalList.init();
		row.add(label);
		row.add(button);
		row.add(unbindBtn);
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
