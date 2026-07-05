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
};
var textComponent: *TextInput = undefined;
var loginButton: *Button = undefined;
var loginAnyways: bool = false;

const padding: f32 = 8;

fn login() void {
	var failureText: main.ListManaged(u8) = .init(main.stackAllocator);
	defer failureText.deinit();
	var accountCode = main.network.authentication.AccountCode.initFromUserInput(textComponent.currentString.items, &failureText);
	defer accountCode.deinit();

	if (accountCode.text.len == 0) {
		main.gui.windowlist.@"cubyz:notification".raiseNotification("Account Code is empty. Please enter a valid Account Code.", .{});
		return;
	}

	if (failureText.items.len != 0 and !loginAnyways) {
		failureText.insertSlice(0, "Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n\n");

		main.gui.windowlist.@"cubyz:notification".raiseNotification("{s}", .{failureText.items});

		loginAnyways = true;
		loginButton.child.label.updateText("Login anyways");

		return;
	}

	main.network.authentication.KeyCollection.init(accountCode);

	gui.closeWindowFromRef(&window);
	gui.windowlist.@"cubyz:authentication/stay_logged_in".setAccountCode(accountCode);
	accountCode = .{.text = &.{}};
	gui.openWindow("cubyz:authentication/stay_logged_in");
}

fn updateText() void {
	loginAnyways = false;
	loginButton.child.label.updateText("Login");
	loginButton.disabled = textComponent.currentString.items.len == 0;
}

fn showTextCallback(showText: bool) void {
	textComponent.obfuscated = !showText;
}

fn none() void {}

fn openCreateAccountWindow() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("cubyz:authentication/create_account_general_info");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 320, 8);
	const width = 480;
	list.add(Label.init(.{0, 0}, width, "You need to login to play Multiplayer", .left));
	list.add(Label.init(.{0, 0}, width, "Please enter your Account Code:", .left));
	const textRow = HorizontalList.init();
	textComponent = TextInput.init(.{0, 0}, 400, 38, "", .{.onNewline = .init(none), .onUpdate = .init(updateText)});
	textComponent.obfuscated = true;
	textComponent.select();
	textRow.add(textComponent);
	textRow.add(CheckBox.init(.{10, 0}, 70, "Show", false, &showTextCallback));
	textRow.finish(.{0, 0}, .center);
	list.add(textRow);
	list.add(Label.init(.{0, 0}, width, "#ff8080**Do not share your Account Code with anyone!**", .left));
	const createAccountRow = HorizontalList.init();
	createAccountRow.add(Label.init(.{0, 3}, 280, "Don't have an Account Code yet?", .left));
	createAccountRow.add(Button.initText(.{0, 0}, 140, "Create Account", .{.onAction = .init(openCreateAccountWindow)}));
	list.add(createAccountRow);
	loginButton = Button.initText(.{padding, 0}, 200, "Login", .{.onAction = .init(login), .disabled = true});
	list.add(loginButton);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the account code or password in memory
	std.crypto.secureZero(@TypeOf(textComponent.textBuffer.glyphs[0]), textComponent.textBuffer.glyphs);
	std.crypto.secureZero(u8, textComponent.currentString.items);
	main.Window.setClipboardString("");
	gui.openWindow("cubyz:clipboard_deleted");

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
