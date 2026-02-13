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
var applyButton: *Button = undefined;
var applyAnyways: bool = false;

var innerList: *VerticalList = undefined;
var encryptWithPasswordCheckbox: *CheckBox = undefined;
var passwordTextField: *TextInput = undefined;

var storeSeedPhrase: bool = false;
var encryptSeedPhrase: bool = true;

const padding: f32 = 8;

fn apply() void {
	var failureText: main.List(u8) = .init(main.stackAllocator);
	defer failureText.deinit();
	const seedPhrase = main.network.authentication.SeedPhrase.initFromUserInput(textComponent.currentString.items, &failureText);
	defer seedPhrase.deinit();

	if (failureText.items.len != 0 and !applyAnyways) {
		failureText.insertSlice(0, "Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n");

		main.gui.windowlist.notification.raiseNotification("{s}", .{failureText.items});

		applyAnyways = true;
		applyButton.child.label.updateText("Apply anyways");

		return;
	}

	if (storeSeedPhrase) {
		if (encryptSeedPhrase) {
			settings.storedAccount.deinit(main.globalAllocator);
			settings.storedAccount = main.network.authentication.PasswordEncodedSeedPhrase.initFromPassword(main.globalAllocator, seedPhrase, passwordTextField.currentString.items);
		} else {
			settings.storedAccount.deinit(main.globalAllocator);
			settings.storedAccount = main.network.authentication.PasswordEncodedSeedPhrase.initUnencoded(main.globalAllocator, seedPhrase);
		}
		settings.save();
	}

	main.network.authentication.KeyCollection.init(seedPhrase);

	gui.closeWindowFromRef(&window);
	if (settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}
}

fn updateText() void {
	applyAnyways = false;
	applyButton.child.label.updateText("Apply");
}

fn showTextCallback(showText: bool) void {
	textComponent.obfuscated = !showText;
}

fn storeSeedPhraseCallback(storeSeedPhrase_: bool) void {
	storeSeedPhrase = storeSeedPhrase_;
	refreshInner();
}

fn encryptSeedPhraseCallback(encryptSeedPhrase_: bool) void {
	encryptSeedPhrase = encryptSeedPhrase_;
	refreshInner();
}

fn refreshInner() void {
	innerList.children.clearRetainingCapacity();
	if (storeSeedPhrase) {
		innerList.children.append(encryptWithPasswordCheckbox.toComponent());
		if (encryptSeedPhrase) {
			innerList.children.append(passwordTextField.toComponent());
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
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "Please enter your account's seed phrase!", .center));
	list.add(Label.init(.{0, 0}, width, "Note: We will only ask for the seed phrase on the start of the game.", .center));
	list.add(Label.init(.{0, 0}, width, "Do not enter your seed phrase under any other circumstance and do not send it to anyone else.", .center));
	textComponent = TextInput.init(.{0, 0}, width, 32, "", .{.onNewline = .init(none), .onUpdate = .init(updateText)});
	textComponent.obfuscated = true;
	list.add(textComponent);
	list.add(CheckBox.init(.{0, 0}, width, "Show text", false, &showTextCallback));
	list.add(CheckBox.init(.{0, 0}, width, "Store seed phrase on disk", storeSeedPhrase, &storeSeedPhraseCallback));
	innerList = VerticalList.init(.{0, 0}, 100, 16);
	encryptWithPasswordCheckbox = CheckBox.init(.{0, 0}, width, "Encrypt it on disk (recommended)", encryptSeedPhrase, &encryptSeedPhraseCallback);
	innerList.add(encryptWithPasswordCheckbox);
	passwordTextField = TextInput.init(.{0, 0}, width, 32, "", .{.onNewline = .init(none)});
	innerList.add(passwordTextField);
	innerList.finish(.center);
	refreshInner();
	list.add(innerList);
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 200, "Create new Account", .init(openCreateAccountWindow)));
	applyButton = Button.initText(.{padding, 0}, 200, "Apply", .init(apply));
	buttonRow.add(applyButton);
	list.add(buttonRow);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the seed phrase in memory
	main.network.authentication.secureZero(@TypeOf(textComponent.textBuffer.glyphs[0]), textComponent.textBuffer.glyphs);
	std.crypto.secureZero(u8, textComponent.currentString.items);
	main.Window.setClipboardString("");

	if (!storeSeedPhrase) {
		encryptWithPasswordCheckbox.deinit();
	}
	if (!encryptSeedPhrase or !storeSeedPhrase) {
		passwordTextField.deinit();
	}

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
