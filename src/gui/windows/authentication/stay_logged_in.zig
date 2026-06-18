const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const CheckBox = GuiComponent.CheckBox;
const Label = GuiComponent.Label;
const HorizontalList = GuiComponent.HorizontalList;
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};

const padding: f32 = 8;

var accountCode: main.network.authentication.AccountCode = undefined;

pub fn setAccountCode(accountCode_: main.network.authentication.AccountCode) void {
	accountCode = accountCode_;
}

fn stayLoggedIn() void {
	gui.windowlist.@"authentication/encrypt_with_password".setAccountCode(accountCode);
	accountCode = .{.text = &.{}};
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/encrypt_with_password");
}

fn dontStayLoggedIn() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("multiplayer");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 160, 8);
	const width = 480;
	list.add(Label.init(.{0, 0}, width, "Would you like to stay logged in?\nThis will store your Account Code locally in your settings file.", .left));
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 70, "No", .{.onAction = .init(dontStayLoggedIn)}));
	buttonRow.add(Button.initText(.{10, 0}, 70, "Yes", .{.onAction = .init(stayLoggedIn)}));
	buttonRow.finish(.{0, 0}, .center);
	list.add(buttonRow);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code or password in memory
	accountCode.deinit();

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
