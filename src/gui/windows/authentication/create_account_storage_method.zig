const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const CheckBox = GuiComponent.CheckBox;
const HorizontalList = GuiComponent.HorizontalList;
const Label = GuiComponent.Label;
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;
const StorageMethod = gui.windowlist.@"authentication/create_account_account_code".StorageMethod;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;

fn next(storageMethod: usize) void {
	gui.closeWindowFromRef(&window);
	gui.windowlist.@"authentication/create_account_account_code".setStorageMethod(@enumFromInt(storageMethod));
	gui.openWindow("authentication/create_account_account_code");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, 300, "Please select how you would like to store your Account Code", .left));
	list.add(Button.initText(.{0, 0}, 300, "Password Manager (recommended)", .{.onAction = .initWithInt(next, @intFromEnum(StorageMethod.passwordManager))}));
	list.add(Button.initText(.{0, 0}, 300, "Save as file", .{.onAction = .initWithInt(next, @intFromEnum(StorageMethod.file))}));
	list.add(Button.initText(.{0, 0}, 300, "Write it down yourself", .{.onAction = .initWithInt(next, @intFromEnum(StorageMethod.paper))}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
