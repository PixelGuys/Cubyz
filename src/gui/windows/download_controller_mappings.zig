const std = @import("std");

const main = @import("root");
const files = main.files;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = @import("../components/Button.zig");
const CheckBox = @import("../components/CheckBox.zig");
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const HorizontalList = @import("../components/HorizontalList.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{256, 256},
	.closeable = false
};

const padding: f32 = 8;
pub var startup_finished: bool = false;
pub fn update() void {
	if (!main.Window.controllerMappingsDownloading()) {
		gui.closeWindowFromRef(&window);
		if(!startup_finished) {
			startup_finished = true;
			if(settings.playerName.len == 0) {
				gui.openWindow("change_name");
			} else {
				gui.openWindow("main");
			}
		}
	}
}
pub fn onOpen() void {
	const label = Label.init(.{padding, 16 + padding}, 300, "Downloading controller mappings...", .center);
	window.rootComponent = label.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
	main.Window.downloadControllerMappings();
}

pub fn onClose() void {
	main.Window.updateControllerMappings();
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
