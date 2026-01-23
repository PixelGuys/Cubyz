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
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
	.closeable = false,
};
var textComponent: *TextInput = undefined;

const padding: f32 = 8;

fn apply() void {
	const seedPhrase = textComponent.currentString.items;
	if (seedPhrase.len < 50) return std.log.err("This is not a valid seed phrase.", .{});
	std.log.info("{s}", .{seedPhrase});

	// Make sure there remains no trace of the seed phrase in memory
	@memset(textComponent.textBuffer.glyphs, std.mem.zeroes(@TypeOf(textComponent.textBuffer.glyphs[0])));
	@memset(textComponent.currentString.items, 0);

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

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "Please enter your account's seed phrase!", .center));
	list.add(Label.init(.{0, 0}, width, "Note: We will only ask for the seed phrase on the start of the game.", .center));
	list.add(Label.init(.{0, 0}, width, "Do not enter your seed phrase under any other circumstance and do not send it to anyone else.", .center));
	textComponent = TextInput.init(.{0, 0}, width, 32, "", .{.onNewline = .init(apply)});
	textComponent.obfuscated = true;
	list.add(textComponent);
	list.add(CheckBox.init(.{0, 0}, width, "Show text", false, &showTextCallback));
	list.add(Button.initText(.{0, 0}, 100, "Apply", .init(apply)));
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
