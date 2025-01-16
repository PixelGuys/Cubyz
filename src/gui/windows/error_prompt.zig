const std = @import("std");

const main = @import("root");
const files = main.files;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Label = @import("../components/Label.zig");

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 64},
	.hasBackground = true,
	.hideIfMouseIsGrabbed = false,
	.relativePosition = .{
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
		.{ .attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower} },
	},
};

const padding: f32 = 8;
pub fn update() void {
	if (main.Window.Gamepad.wereControllerMappingsDownloaded()) {
		gui.closeWindowFromRef(&window);
	}
}
pub fn onOpen() void {
	const label = Label.init(.{padding, 16 + padding}, 128, "#ffff00The game encountered errors. Check the logs for details", .center);
	window.rootComponent = label.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
