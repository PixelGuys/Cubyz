const std = @import("std");

const main = @import("main");
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};
var textComponent: *TextInput = undefined;

const padding: f32 = 8;

fn apply(_: usize) void {
	if(textComponent.currentString.items.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(textComponent.currentString.items) > 50) {
		std.log.err("Name is too long with {}/{} characters. Limits are 50/500", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(textComponent.currentString.items), textComponent.currentString.items.len});
		return;
	}
	const oldName = settings.playerName;
	main.globalAllocator.free(settings.playerName);
	settings.playerName = main.globalAllocator.dupe(u8, textComponent.currentString.items);
	settings.save();

	gui.closeWindowFromRef(&window);
	if(oldName.len == 0) {
		gui.openWindow("main");
	}
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 420;
	if(settings.playerName.len == 0) {
		list.add(Label.init(.{0, 0}, width, "Please enter your name!", .center));
		window.closeable = false;
	} else {
		list.add(Label.init(.{0, 0}, width, "#ff0000Warning: #ffffffYou lose access to your inventory data when changing the name!", .center));
		window.closeable = true;
	}
	list.add(Label.init(.{0, 0}, width, "Cubyz supports formatting your username using a markdown-like syntax:", .center));
	list.add(Label.init(.{0, 0}, width, "\\**italic*\\* \\*\\***bold**\\*\\* \\_\\___underlined__\\_\\_ \\~\\~~~strike-through~~\\~\\~", .center));
	list.add(Label.init(.{0, 0}, width, "Even colors are possible, using the hexadecimal color code:", .center));
	list.add(Label.init(.{0, 0}, width, "\\##ff0000ff#ffffff00#ffffff00#ff0000red#ffffff \\##ff0000ff#00770077#ffffff00#ff7700orange#ffffff \\##ffffff00#00ff00ff#ffffff00#00ff00green#ffffff \\##ffffff00#ffffff00#0000ffff#0000ffblue", .center));
	textComponent = TextInput.init(.{0, 0}, width, 32, if(settings.playerName.len == 0) "quanturmdoelvloper" else settings.playerName, .{.callback = &apply});
	list.add(textComponent);
	list.add(Button.initText(.{0, 0}, 100, "Apply", .{.callback = &apply}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
