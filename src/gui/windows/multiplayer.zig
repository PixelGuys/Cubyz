const std = @import("std");

const main = @import("main");
const settings = main.settings;
const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const Label = GuiComponent.Label;
const TextInput = GuiComponent.TextInput;
const VerticalList = GuiComponent.VerticalList;
const Vec2f = main.vec.Vec2f;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

var nameEntry: *TextInput = undefined;

const padding: f32 = 8;

fn applyName() void {
	if (nameEntry.currentString.items.len > 500 or main.graphics.TextBuffer.Parser.countVisibleCharacters(nameEntry.currentString.items) > 50) {
		std.log.err("Name is too long with {}/{} characters. Limits are 50/500", .{main.graphics.TextBuffer.Parser.countVisibleCharacters(nameEntry.currentString.items), nameEntry.currentString.items.len});
		return;
	}
	if (std.mem.eql(u8, nameEntry.currentString.items, settings.playerName)) return;
	main.globalAllocator.free(settings.playerName);
	settings.playerName = main.globalAllocator.dupe(u8, nameEntry.currentString.items);
	settings.save();
}

fn hostWorld() void {
	applyName();
	gui.windowlist.save_selection.mode = .multiplayer;
	gui.closeWindow("save_selection");
	gui.openWindow("save_selection");
}

fn joinServer() void {
	applyName();
	gui.openWindow("multiplayer_join");
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, 200, "Name:", .center));
	nameEntry = TextInput.init(.{0, 0}, 200, 32, settings.playerName, .{.onNewline = .init(applyName)});
	list.add(nameEntry);
	list.add(Button.initText(.{0, 0}, 128, "Host World", .{.onAction = .init(hostWorld)}));
	list.add(Button.initText(.{0, 0}, 128, "Join Server", .{.onAction = .init(joinServer)}));
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
