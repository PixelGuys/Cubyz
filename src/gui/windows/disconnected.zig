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

pub var reasonCode: main.network.Connection.DisconnectReason = .worldClosed;
var reason: []const u8 = "";

pub fn init() void {
	reason = "";
	if(reasonCode != .worldClosed) {
		setDisconnectedReason(reasonCode);
	}
}

pub fn deinit() void {
	main.globalAllocator.free(reason);
}

fn ack(_: usize) void {
	reasonCode = .worldClosed;
	gui.closeWindowFromRef(&window);
}

pub fn setDisconnectedReason(newReasonCode: main.network.Connection.DisconnectReason) void {
	if(newReasonCode != .worldClosed) {
		main.globalAllocator.free(reason);
		reasonCode = newReasonCode;
		reason = main.globalAllocator.dupe(u8, switch(newReasonCode) {
			.kicked => "You were kicked from the server.",
			.serverStopped => "The server has server stopped.",
			.badPacket => "Invalid network packet received.",
			.alreadyConnected => "You are already connected.",
			.timeout => "Connection timed out.",
			else => "",
		});
	}
}

pub fn showDisconnectReason() void {
	if(reasonCode != .worldClosed) {
		gui.openWindowFromRef(&window);
	}
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
