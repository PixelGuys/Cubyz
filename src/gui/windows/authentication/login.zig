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

const padding: f32 = 8;

fn apply() void {
	var failureText: main.List(u8) = .init(main.stackAllocator);
	defer failureText.deinit();
	const seedPhrase = main.network.authentication.SeedPhrase.initFromUserInput(textComponent.currentString.items, &failureText);
	defer seedPhrase.deinit();

	if(failureText.items.len != 0 and !applyAnyways) {
		failureText.insertSlice(0, "Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n");

		main.gui.windowlist.notification.raiseNotification("{s}", .{failureText.items});

		applyAnyways = true;
		applyButton.child.label.updateText("Apply anyways");

		return;
	}

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

fn openCreateAccountWindow() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/create_account");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "Please enter your account's seed phrase!", .center));
	list.add(Label.init(.{0, 0}, width, "Note: We will only ask for the seed phrase on the start of the game.", .center));
	list.add(Label.init(.{0, 0}, width, "Do not enter your seed phrase under any other circumstance and do not send it to anyone else.", .center));
	textComponent = TextInput.init(.{0, 0}, width, 32, "", .{.onNewline = .init(apply), .onUpdate = .init(updateText)});
	textComponent.obfuscated = true;
	list.add(textComponent);
	list.add(CheckBox.init(.{0, 0}, width, "Show text", false, &showTextCallback));
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
	@memset(textComponent.textBuffer.glyphs, std.mem.zeroes(@TypeOf(textComponent.textBuffer.glyphs[0])));
	@memset(textComponent.currentString.items, 0);
	main.Window.setClipboardString("");

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
