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
const width: f32 = 300;

var addressEntry: *TextInput = undefined;
var joinButton: *Button = undefined;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

fn onEnterName(_: usize) void {
	addressEntry.select();
}

fn join(_: usize) void {
	const address = addressEntry.currentString.items;
	_ = main.game.join(address, null);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 380, padding);
	list.add(Label.init(.{0, 0}, width, "Enter server address", .center));
	addressEntry = TextInput.init(.{0, 0}, width, 24, "", .{.callback = &join}, .{});
	list.add(addressEntry);
	joinButton = Button.initText(.{0, 0}, width/3, "Join", .{.callback = &join});
	joinButton.disabled = true;
	list.add(joinButton);
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
	const address = addressEntry.currentString.items;
	joinButton.disabled = address.len == 0 or std.mem.indexOfAny(u8, address, " \n\r\t<>!@#$%^&*(){}=+/*~,;\"\'\\") != null;
}
