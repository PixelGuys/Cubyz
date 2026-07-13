const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const c = @import("c");

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const VerticalList = @import("../components/VerticalList.zig");
const run_settings = @import("../../run_settings.zig");

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeable = false,
};

const padding: f32 = 8;

fn checkRunMode() void {
	switch (run_settings.runMode) {
		.normal => return,
		.first => singleplayerSelection(),
		.world => singleplayerSelection(),
	}
}
fn exitGame() void {
	c.glfwSetWindowShouldClose(main.Window.window, c.GLFW_TRUE);
}
fn singleplayerSelection() void {
	gui.windowlist.save_selection.mode = .singleplayer;
	gui.closeWindow("save_selection");
	gui.openWindow("save_selection");
}
fn multiplayer() void {
	if (main.network.authentication.KeyCollection.initialized) {
		gui.openWindow("multiplayer");
		return;
	}
	switch (main.settings.storedAccount.typ) {
		.none => {
			if (main.settings.storedAccount.data.len == 0) {
				gui.openWindow("authentication/login");
				return;
			}
			var failureText: main.ListManaged(u8) = .init(main.stackAllocator);
			defer failureText.deinit();
			const accountCode = main.settings.storedAccount.decryptFromPassword(undefined, &failureText) catch |err| {
				std.log.err("Got error while loading Account Code: {s}", .{@errorName(err)});
				gui.openWindow("authentication/login");
				return;
			};
			defer accountCode.deinit();
			if (failureText.items.len != 0) {
				std.log.warn("Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n{s}", .{failureText.items});
			}
			main.network.authentication.KeyCollection.init(accountCode);
			gui.openWindow("multiplayer");
		},
		else => {
			gui.openWindow("authentication/unlock");
		},
	}
}
pub fn onOpen() void {
	checkRunMode();
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Singleplayer", .{.onAction = .init(singleplayerSelection)}));
	list.add(Button.initText(.{0, 0}, 128, "Multiplayer", .{.onAction = .init(multiplayer)}));
	list.add(Button.initText(.{0, 0}, 128, "Settings", .{.onAction = gui.openWindowCallback("settings")}));
	list.add(Button.initText(.{0, 0}, 128, "Touch Grass", .{.onAction = .init(exitGame)}));
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
