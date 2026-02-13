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

var seedPhraseLabel: *Label = undefined;
var seedPhrase: main.network.authentication.SeedPhrase = undefined;

fn next() void {
	gui.closeWindowFromRef(&window);
	gui.openWindow("authentication/login");
}

fn copy() void {
	main.Window.setClipboardString(seedPhrase.text);
}

pub fn onOpen() void {
	seedPhrase = .initRandomly();

	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	list.add(Label.init(.{0, 0}, width, "This is your account's seed phrase:", .left));
	const row = HorizontalList.init();
	seedPhraseLabel = Label.init(.{0, 0}, 350, seedPhrase.text, .left);
	row.add(seedPhraseLabel);
	row.add(Button.initText(.{0, 0}, 70, "Copy", .init(copy)));
	list.add(row);
	list.add(Label.init(.{0, 0}, width, "Note: Do not give this to anyone else. We will only ask for the seed phrase on the start of the game.", .left));
	list.add(Label.init(.{0, 0}, width, "Note 2: Make sure you store this somewhere safely and securely, there is no recovery option if you lose it. We recommend a password manager.", .left));
	list.add(Button.initText(.{0, 0}, 70, "Next", .init(next)));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	// Make sure there remains no trace of the seed phrase in memory
	main.network.authentication.secureZero(@TypeOf(seedPhraseLabel.text.glyphs[0]), seedPhraseLabel.text.glyphs);
	seedPhrase.deinit();
	// This also serves as a measure to ensure that the user indeed copied it somewhere else before closing the window
	main.Window.setClipboardString("");

	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
