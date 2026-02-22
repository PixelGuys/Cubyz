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
var textComponent: *TextInput = undefined;
var loginButton: *Button = undefined;
var loginAnyways: bool = false;

var innerList: *VerticalList = undefined;
var encryptWithPasswordCheckbox: *CheckBox = undefined;
var passwordTextField: *TextInput = undefined;
var passwordRow: *HorizontalList = undefined;

var storeAccountCode: bool = false;
var encryptAccountCode: bool = true;

const padding: f32 = 8;

fn login() void {
	var failureText: main.List(u8) = .init(main.stackAllocator);
	defer failureText.deinit();
	const accountCode = main.network.authentication.AccountCode.initFromUserInput(textComponent.currentString.items, &failureText);
	defer accountCode.deinit();

	if (accountCode.text.len == 0) {
		main.gui.windowlist.notification.raiseNotification("Account Code is empty. Please enter a valid Account Code.", .{});
		return;
	}

	if (failureText.items.len != 0 and !loginAnyways) {
		failureText.insertSlice(0, "Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n\n");

		main.gui.windowlist.notification.raiseNotification("{s}", .{failureText.items});

		loginAnyways = true;
		loginButton.child.label.updateText("Login anyways");

		return;
	}

	if (storeAccountCode) {
		if (encryptAccountCode) {
			settings.storedAccount.deinit(main.globalAllocator);
			settings.storedAccount = .initFromPassword(main.globalAllocator, accountCode, passwordTextField.currentString.items);
		} else {
			settings.storedAccount.deinit(main.globalAllocator);
			settings.storedAccount = .initUnencoded(main.globalAllocator, accountCode);
		}
		settings.save();
	}

	main.network.authentication.KeyCollection.init(accountCode);

	gui.closeWindowFromRef(&window);
	if (settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}
}

fn updateText() void {
	loginAnyways = false;
	loginButton.child.label.updateText("Login");
}

fn showTextCallback(showText: bool) void {
	textComponent.obfuscated = !showText;
}

fn storeAccountCodeCallback(storeAccountCode_: bool) void {
	storeAccountCode = storeAccountCode_;
	refreshInner();
}

fn encryptAccountCodeCallback(encryptAccountCode_: bool) void {
	encryptAccountCode = encryptAccountCode_;
	refreshInner();
}

fn refreshInner() void {
	innerList.children.clearRetainingCapacity();
	if (storeAccountCode) {
		innerList.children.append(encryptWithPasswordCheckbox.toComponent());
		if (encryptAccountCode) {
			innerList.children.append(passwordRow.toComponent());
		}
	}
}

fn none() void {}

fn openCreateAccountWindow() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/create_account");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 320, 8);
	const width = 480;
	list.add(Label.init(.{0, 0}, width, "Please enter your Account Code:", .left));
	const textRow = HorizontalList.init();
	textComponent = TextInput.init(.{0, 0}, 400, 38, "", .{.onNewline = .init(none), .onUpdate = .init(updateText)});
	textComponent.obfuscated = true;
	textRow.add(textComponent);
	textRow.add(CheckBox.init(.{10, 0}, 70, "Show", false, &showTextCallback));
	textRow.finish(.{0, 0}, .center);
	list.add(textRow);
	list.add(Label.init(.{0, 0}, width, "#ff8080**Do not share your Account Code with anyone!**", .left));
	const createAccountRow = HorizontalList.init();
	createAccountRow.add(Label.init(.{0, 3}, 240, "Don't have an Account Code yet?", .left));
	createAccountRow.add(Button.initText(.{0, 0}, 140, "Create Account", .init(openCreateAccountWindow)));
	list.add(createAccountRow);
	list.add(CheckBox.init(.{0, 0}, width, "Store Account Code on disk", storeAccountCode, &storeAccountCodeCallback));
	innerList = VerticalList.init(.{0, 0}, 100, 16);
	encryptWithPasswordCheckbox = CheckBox.init(.{0, 0}, width, "Encrypt it on disk (recommended)", encryptAccountCode, &encryptAccountCodeCallback);
	innerList.add(encryptWithPasswordCheckbox);
	passwordRow = HorizontalList.init();
	passwordRow.add(Label.init(.{0, 0}, 130, "Local Password:", .left));
	passwordTextField = TextInput.init(.{0, 0}, width - 130, 22, "", .{.onNewline = .init(none)});
	passwordRow.add(passwordTextField);
	passwordRow.finish(.{0, 0}, .center);
	innerList.add(passwordRow);
	innerList.finish(.center);
	refreshInner();
	list.add(innerList);
	loginButton = Button.initText(.{padding, 0}, 200, "Login", .init(login));
	list.add(loginButton);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code or password in memory
	main.network.authentication.secureZero(@TypeOf(textComponent.textBuffer.glyphs[0]), textComponent.textBuffer.glyphs);
	std.crypto.secureZero(u8, textComponent.currentString.items);
	main.network.authentication.secureZero(@TypeOf(passwordTextField.textBuffer.glyphs[0]), passwordTextField.textBuffer.glyphs);
	std.crypto.secureZero(u8, passwordTextField.currentString.items);
	main.Window.setClipboardString("");
	gui.openWindow("clipboard_deleted");

	if (!storeAccountCode) {
		encryptWithPasswordCheckbox.deinit();
	}
	if (!encryptAccountCode or !storeAccountCode) {
		passwordRow.deinit();
	}

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
