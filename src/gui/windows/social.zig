const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const HorizontalList = @import("../components/HorizontalList.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");

pub var window: GuiWindow = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeIfMouseIsGrabbed = true,
};

const padding: f32 = 8;
var key: []const u8 = undefined;

fn toggleStreamerMode(value: bool) void {
	main.settings.streamerMode = value;
	main.settings.save();
}

fn logout() void {
	main.settings.storedAccount.deinit(main.globalAllocator);
	main.settings.storedAccount = .empty;
	main.settings.save();
	for (gui.openWindows.items) |openWindow| {
		gui.closeWindowFromRef(openWindow);
	}
	gui.openWindow("authentication/login");
}

fn copy() void {
	main.Window.setClipboardString(key);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 400, 16);
	list.add(CheckBox.init(.{0, 0}, 316, "Streamer Mode (hides sensitive data)", main.settings.streamerMode, &toggleStreamerMode));
	key = main.network.authentication.KeyCollection.getPublicKey(main.globalAllocator, .ed25519);
	const row = HorizontalList.init();
	list.add(Label.init(.{0, 0}, 128, "Your public key", .left));
	row.add(Label.init(.{0, 0}, 200, key, .left));
	row.add(Button.initText(.{padding, 0}, 70, "Copy", .init(copy)));
	list.add(row);
	if (main.game.world == null) {
		list.add(Button.initText(.{0, 0}, 128, "Change Name", gui.openWindowCallback("change_name")));
		list.add(Button.initText(.{0, 0}, 128, "Logout", .init(logout)));
	}
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	main.globalAllocator.free(key);
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
