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

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;
var enableTime: std.Io.Timestamp = undefined;
var button: *Button = undefined;

fn next() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/create_account_storage_method");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "An Account Code acts as a password and identity.", .left));
	list.add(Label.init(.{0, 0}, width, "If you lose your Account Code, you lose your Account. There are no recovery options, so please store it somewhere safe.", .left));
	button = Button.initText(.{0, 0}, 300, "Continue", .{.onAction = .init(next), .disabled = true});
	list.add(button);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
	enableTime = main.timestamp().addDuration(.fromSeconds(8));
}

pub fn update() void {
	if (enableTime.nanoseconds < main.timestamp().nanoseconds) {
		button.disabled = false;
	}
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
