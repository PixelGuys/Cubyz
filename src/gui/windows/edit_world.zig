const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;
const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const ZonElement = main.ZonElement;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const TextInput = @import("../components/TextInput.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const VerticalList = @import("../components/VerticalList.zig");

fn pass() void {}

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 8;

var editWorldName: []const u8 = "";

var worldInfo: *ZonElement = undefined;

var nameInput: *TextInput = undefined;

pub fn init() void {
	editWorldName = "";
}

pub fn deinit() void {
	main.globalAllocator.free(editWorldName);
}

pub fn setEditWorldName(name: []const u8) void {
	main.globalAllocator.free(editWorldName);
	editWorldName = main.globalAllocator.dupe(u8, name);
}

pub fn onOpen() void {
	//const list = VerticalList.init(.{ padding, 16 + padding }, 300, 8);

	//    nameInput = TextInput.init(.{ 0, 0 }, 128, 22, editWorldName, .{ .onNewline = .init(pass) });
	//    list.add(nameInput);

	//list.finish(.center);
	//window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
