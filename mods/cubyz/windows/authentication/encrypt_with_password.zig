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

var innerList: *VerticalList = undefined;
var encryptWithPasswordCheckbox: *CheckBox = undefined;
var passwordTextField: *TextInput = undefined;
var passwordRow: *HorizontalList = undefined;

var confirmButton: *Button = undefined;

var encryptAccountCode: bool = true;

const padding: f32 = 8;

var accountCode: main.network.authentication.AccountCode = undefined;

pub fn setAccountCode(accountCode_: main.network.authentication.AccountCode) void {
	accountCode = accountCode_;
}

fn confirm() void {
	if (encryptAccountCode) {
		settings.storedAccount.deinit(main.globalAllocator);
		settings.storedAccount = .initFromPassword(main.globalAllocator, accountCode, passwordTextField.currentString.items);
	} else {
		settings.storedAccount.deinit(main.globalAllocator);
		settings.storedAccount = .initUnencoded(main.globalAllocator, accountCode);
	}
	settings.save();

	gui.closeWindowFromRef(&window);
	gui.openWindow("cubyz:multiplayer");
}

fn encryptAccountCodeCallback(encryptAccountCode_: bool) void {
	encryptAccountCode = encryptAccountCode_;
	refreshInner();
}

fn refreshInner() void {
	innerList.children.clearRetainingCapacity();
	innerList.children.append(encryptWithPasswordCheckbox.toComponent());
	if (encryptAccountCode) {
		innerList.children.append(passwordRow.toComponent());
	}
}

fn back() void {
	gui.windows.@"cubyz:authentication/stay_logged_in".setAccountCode(accountCode);
	accountCode = .{.text = &.{}};
	gui.closeWindowFromRef(&window);
	gui.openWindow("cubyz:authentication/stay_logged_in");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 320, 8);
	const width = 480;
	list.add(Label.init(.{0, 0}, width, "Your Account Code will be stored in your settings to allow you to stay logged in. Please decide how we should store it:", .left));
	innerList = VerticalList.init(.{0, 0}, 100, 16);
	encryptWithPasswordCheckbox = CheckBox.init(.{0, 0}, width, "Encrypt it with a password (recommended)\n(The password needs to be entered every time)", encryptAccountCode, &encryptAccountCodeCallback);
	innerList.add(encryptWithPasswordCheckbox);
	passwordRow = HorizontalList.init();
	passwordRow.add(Label.init(.{0, 0}, 130, "Local Password:", .left));
	passwordTextField = TextInput.init(.{0, 0}, width - 130, 22, "", .{.onNewline = .{}});
	passwordRow.add(passwordTextField);
	passwordRow.finish(.{0, 0}, .center);
	innerList.add(passwordRow);
	innerList.finish(.center);
	refreshInner();
	list.add(innerList);
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 70, "Back", .{.onAction = .init(back)}));
	confirmButton = Button.initText(.{10, 0}, 70, "Confirm", .{.onAction = .init(confirm)});
	buttonRow.add(confirmButton);
	buttonRow.finish(.{0, 0}, .center);
	list.add(buttonRow);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn update() void {
	confirmButton.disabled = encryptAccountCode and passwordTextField.currentString.items.len == 0;
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code or password in memory
	accountCode.deinit();
	main.Window.setClipboardString("");
	gui.openWindow("cubyz:clipboard_deleted");

	if (!encryptAccountCode) {
		passwordRow.deinit();
	}

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
