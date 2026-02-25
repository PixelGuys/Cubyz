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

var textComponent: *TextInput = undefined;

fn apply() void {
	var failureText: main.List(u8) = .init(main.stackAllocator);
	defer failureText.deinit();
	const accountCode = main.settings.storedAccount.decryptFromPassword(textComponent.currentString.items, &failureText) catch |err| {
		std.log.err("Encountered error while decrypting password: {s}", .{@errorName(err)});
		return;
	};
	defer accountCode.deinit();

	if (failureText.items.len != 0) {
		std.log.warn("Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n{s}", .{failureText.items});
	}

	main.network.authentication.KeyCollection.init(accountCode);

	gui.closeWindowFromRef(&window);
	if (settings.playerName.len == 0) {
		gui.openWindow("change_name");
	} else {
		gui.openWindow("main");
	}
}

fn showTextCallback(showText: bool) void {
	textComponent.obfuscated = !showText;
}

fn logout() void {
	main.settings.storedAccount.deinit(main.globalAllocator);
	main.settings.storedAccount = .empty;
	main.settings.save();
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/login");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 320, 8);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "Please enter your local password!", .left));
	list.add(Label.init(.{0, 0}, width, "If you lost your password you can also log out and reenter your Account Code.", .left));
	const passwordRow = HorizontalList.init();
	textComponent = TextInput.init(.{0, 0}, width - 80, 22, "", .{.onNewline = .init(apply)});
	textComponent.obfuscated = true;
	passwordRow.add(textComponent);
	passwordRow.add(CheckBox.init(.{10, 0}, 70, "Show", false, &showTextCallback));
	passwordRow.finish(.{0, 0}, .center);
	list.add(passwordRow);
	const buttonRow = HorizontalList.init();
	buttonRow.add(Button.initText(.{0, 0}, 200, "Logout", .init(logout)));
	buttonRow.add(Button.initText(.{padding, 0}, 200, "Unlock", .init(apply)));
	list.add(buttonRow);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the password in memory
	main.network.authentication.secureZero(@TypeOf(textComponent.textBuffer.glyphs[0]), textComponent.textBuffer.glyphs);
	std.crypto.secureZero(u8, textComponent.currentString.items);
	main.Window.setClipboardString("");
	gui.openWindow("clipboard_deleted");

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
