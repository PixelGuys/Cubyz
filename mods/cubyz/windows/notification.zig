const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;
const Button = GuiComponent.Button;
const VerticalList = GuiComponent.VerticalList;
const Label = GuiComponent.Label;

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 16;
const width: f32 = 256;

var text: []const u8 = "";

pub fn deinit() void {
	main.globalAllocator.free(text);
	text = "";
}

fn setNotificationText(comptime formatText: []const u8, args: anytype) void {
	main.globalAllocator.free(text);
	text = std.fmt.allocPrint(main.globalAllocator.allocator, formatText, args) catch unreachable;
}

pub fn raiseNotification(comptime formatText: []const u8, args: anytype) void {
	main.gui.closeWindow("cubyz:notification");
	setNotificationText(formatText, args);
	main.gui.openWindow("cubyz:notification");
}

fn ack() void {
	gui.closeWindowFromRef(&window);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, text, .left));
	list.add(Button.initText(.{0, 0}, 100, "OK", .{.onAction = .init(ack)}));
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
