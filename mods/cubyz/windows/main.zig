const std = @import("std");

const main = @import("main");
const Vec2f = main.vec.Vec2f;

const c = @import("c");

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = GuiComponent.Button;
const VerticalList = GuiComponent.VerticalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 256},
	.closeable = false,
};

const padding: f32 = 8;

fn exitGame() void {
	c.glfwSetWindowShouldClose(main.Window.window, c.GLFW_TRUE);
}
fn singleplayerSelection() void {
	gui.windows.@"cubyz:save_selection".mode = .singleplayer;
	gui.closeWindow("cubyz:save_selection");
	gui.openWindow("cubyz:save_selection");
}
fn multiplayer() void {
	if (main.network.authentication.KeyCollection.initialized) {
		gui.openWindow("cubyz:multiplayer");
		return;
	}
	switch (main.settings.storedAccount.typ) {
		.none => {
			if (main.settings.storedAccount.data.len == 0) {
				gui.openWindow("cubyz:authentication/login");
				return;
			}
			var failureText: main.ListManaged(u8) = .init(main.stackAllocator);
			defer failureText.deinit();
			const accountCode = main.settings.storedAccount.decryptFromPassword(undefined, &failureText) catch |err| {
				std.log.err("Got error while loading Account Code: {s}", .{@errorName(err)});
				gui.openWindow("cubyz:authentication/login");
				return;
			};
			defer accountCode.deinit();
			if (failureText.items.len != 0) {
				std.log.warn("Encountered errors while verifying your Account. This may happen if you created your account in a future version, in which case it's fine to continue.\n{s}", .{failureText.items});
			}
			main.network.authentication.KeyCollection.init(accountCode);
			gui.openWindow("cubyz:multiplayer");
		},
		else => {
			gui.openWindow("cubyz:authentication/unlock");
		},
	}
}
pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Button.initText(.{0, 0}, 128, "Singleplayer", .{.onAction = .init(singleplayerSelection)}));
	list.add(Button.initText(.{0, 0}, 128, "Multiplayer", .{.onAction = .init(multiplayer)}));
	list.add(Button.initText(.{0, 0}, 128, "Settings", .{.onAction = gui.openWindowCallback("cubyz:settings")}));
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
