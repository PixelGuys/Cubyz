const std = @import("std");

const main = @import("main");
const settings = main.settings;
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
	const key = main.network.authentication.KeyCollection.getPublicKey(main.globalAllocator, settings.launchConfig.preferredAuthenticationAlgorithm);
	defer main.globalAllocator.free(key);
	main.Window.setClipboardString(key);
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 400, 16);
	list.add(CheckBox.init(.{0, 0}, 316, "Streamer Mode (hides sensitive data)", main.settings.streamerMode, &toggleStreamerMode));
	list.add(Button.initText(.{0, 0}, 150, "Copy public key", .init(copy)));
	if (main.game.world == null) {
		list.add(Button.initText(.{0, 0}, 150, "Change Name", gui.openWindowCallback("change_name")));
		list.add(Button.initText(.{0, 0}, 150, "Logout", .init(logout)));
	}
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
