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

var pos: main.vec.Vec3i = undefined;
var oldText: []const u8 = &.{};

pub fn openFromSignData(_pos: main.vec.Vec3i, _oldText: []const u8) void {
	pos = _pos;
	std.debug.assert(oldText.len == 0);
	oldText = main.globalAllocator.dupe(u8, _oldText);
	gui.openWindowFromRef(&window);
	main.Window.setMouseGrabbed(false);
}

fn apply(_: usize) void {
	if(textComponent.currentString.items.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(textComponent.currentString.items) > 100) {
		std.log.err("Text is too long with {}/{} characters. Limits are 100/500", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(textComponent.currentString.items), textComponent.currentString.items.len});
		return;
	}

	std.log.err("TODO: Update block entity data for block at {} to {s}", .{pos, textComponent.currentString.items});

	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	const width = 120;
	textComponent = TextInput.init(.{0, 0}, width, 32*4, oldText, .{.callback = &apply}, .{});
	list.add(textComponent);
	list.add(Button.initText(.{0, 0}, 100, "Apply", .{.callback = &apply}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	main.globalAllocator.free(oldText);
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
