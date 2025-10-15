const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const VerticalList = @import("../components/VerticalList.zig");
const multiplayer = @import("multiplayer.zig");

const padding: f32 = 8;
const width: f32 = 380;

var nameEntry: *TextInput = undefined;
var addressEntry: *TextInput = undefined;
var addButton: *Button = undefined;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

fn onEnterName(_: usize) void {
	addressEntry.select();
}

fn isCorrectInput(name: []const u8, address: []const u8) bool {
	const trimName = std.mem.trim(u8, name, " \t");
	if(trimName.len == 0 or address.len == 0) return false;

	const isNameWrong = std.mem.indexOfAny(u8, trimName, "\n\r\t") != null;
	const isAddressWrong = std.mem.indexOfAny(u8, address, " \n\r\t<>!@#$%^&*(){}=+/*~,;\"\'\\") != null;
	if(isNameWrong or isAddressWrong) return false;

	return true;
}

fn addServer(_: usize) void {
	const name = nameEntry.currentString.items;
	const trimName = std.mem.trim(u8, name, " \t");
	const address = addressEntry.currentString.items;

	multiplayer.addServer(trimName, address);
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 380, padding);
	list.add(Label.init(.{0, 0}, width, "Name:", .left));
	nameEntry = TextInput.init(.{0, 0}, width, 24, "My Server", .{.callback = &onEnterName}, .{});
	list.add(nameEntry);
	list.add(Label.init(.{0, 0}, width, "Address:", .left));
	addressEntry = TextInput.init(.{0, 0}, width, 24, "", .{.callback = &addServer}, .{});
	list.add(addressEntry);
	addButton = Button.initText(.{0, 0}, 100, "Add", .{.callback = &addServer});
	addButton.disabled = true;
	list.add(addButton);
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	window.scale = 1;
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}

pub fn update() void {
	const name = nameEntry.currentString.items;
	const address = addressEntry.currentString.items;

	addButton.disabled = !isCorrectInput(name, address);
}
