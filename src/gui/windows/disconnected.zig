const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const Button = @import("../components/Button.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
};

const padding: f32 = 16;
const width: f32 = 256;

var reason: []const u8 = "";

pub fn setDisconnectedReason(newReason: [] const u8) void {
	main.globalAllocator.free(reason);
	reason = main.globalAllocator.dupe(u8, newReason);
}

pub fn showDisconnectReason() void {
	if(reason.len > 0){
		gui.openWindowFromRef(&window);
	}
}

fn ack(_: usize) void {
	gui.closeWindowFromRef(&window);
	main.globalAllocator.free(reason);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{0, 0}, width, reason, .center));
	list.add(Button.initText(.{0, 0}, 100, "OK", .{.callback = &ack}));
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