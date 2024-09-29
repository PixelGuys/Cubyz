const std = @import("std");

const main = @import("root");
const Vec2f = main.vec.Vec2f;
const c = main.Window.c;
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
var kbd: bool = true;
var needsUpdate: bool = false;
fn keyFunction(keyPtr: usize) void {
	main.Window.setNextKeypressListener(&keypressListener) catch return;
	selectedKey = @ptrFromInt(keyPtr);
	needsUpdate = true;
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
fn keypressListener(key: c_int, mouseButton: c_int, scancode: c_int) void {
	selectedKey.?.key = key;
	selectedKey.?.mouseButton = mouseButton;
	selectedKey.?.scancode = scancode;
	selectedKey = null;
	needsUpdate = true;
	main.settings.save();
}

fn updateSensitivity(sensitivity: f32) void {
	if (kbd) {
		main.settings.mouseSensitivity = sensitivity;
	} else {
		main.settings.controllerSensitivity = sensitivity;
	}
	main.settings.save();
}

fn updateDeadzone(deadzone: f32) void {
	main.settings.controllerAxisDeadzone = deadzone;
}

fn deadzoneFormatter(allocator: main.utils.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "Deadzone: {d:.0}%", .{value*100}) catch unreachable;
}

fn sensitivityFormatter(allocator: main.utils.NeverFailingAllocator, value: f32) []const u8 {
	return std.fmt.allocPrint(allocator.allocator, "{s} Sensitivity: {d:.0}%", .{if (kbd) "Mouse" else "Controller", value*100}) catch unreachable;
}

fn setKeyboard(isKeyboard: usize) void {
	kbd = isKeyboard != 0;
	needsUpdate = true;
}
fn unbindKey(keyPtr: usize) void {
	var key: ?*main.Window.Key = @ptrFromInt(keyPtr);
	if (kbd) {
		key.?.key = c.GLFW_KEY_UNKNOWN;
		key.?.mouseButton = -1;
		key.?.scancode = 0;
	} else {
		key.?.gamepadAxis = null;
		key.?.gamepadButton = -1;
	}
	needsUpdate = true;
}
fn cancelBindKey(_: usize) void {
	selectedKey = null;
	needsUpdate = true;
}
fn resetKeyBinding(keyPtr: usize) void {
	const key: ?*main.Window.Key = @ptrFromInt(keyPtr);
	main.KeyBoard.resetKey(key.?.name);
	selectedKey = null;
	needsUpdate = true;
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 428, 8);
	list.add(Button.initText(.{0, 0}, 128, if (kbd) "Gamepad" else "Keyboard", .{.callback = &setKeyboard, .arg = if (kbd) 0 else 1}));
	list.add(ContinuousSlider.init(.{0, 0}, 256, 0, 5, if (kbd) main.settings.mouseSensitivity else main.settings.controllerSensitivity, &updateSensitivity, &sensitivityFormatter));
	if (!kbd) {
		list.add(ContinuousSlider.init(.{0, 0}, 256, 0, 5, main.settings.controllerAxisDeadzone, &updateDeadzone, &deadzoneFormatter));
	}
	for(&main.KeyBoard.keys) |*key| {
		const label = Label.init(.{0, 0}, 128, key.name, .left);
		const button = if(key == selectedKey) (
			Button.initText(.{16, 0}, 128, "...", .{})
		) else (
			Button.initText(.{16, 0}, 128, if (kbd) key.getName() else key.getGamepadName(), .{.callback = if (kbd) &keyFunction else &gamepadFunction, .arg = @intFromPtr(key)})
		);
		const row = HorizontalList.init();
		row.add(label);
		row.add(button);
		if (key == selectedKey) {

			const cancelBtn = Button.initText(.{16, 0}, 128, "Cancel", .{.callback = &cancelBindKey, .arg = 0});
			row.add(cancelBtn);
		} else {
			const resetBtn = Button.initText(.{16, 0}, 64, "Reset", .{.callback = &resetKeyBinding, .arg = @intFromPtr(key)});
			const unbindBtn = Button.initText(.{16, 0}, 64, "Unbind", .{.callback = &unbindKey, .arg = @intFromPtr(key)});
			row.add(resetBtn);
			row.add(unbindBtn);
		}
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
