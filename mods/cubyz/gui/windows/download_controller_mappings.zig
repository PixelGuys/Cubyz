const std = @import("std");

const main = @import("main");
const files = main.files;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;

const gui = main.gui;
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;
const Button = gui.Button;
const CheckBox = gui.CheckBox;
const Label = gui.Label;
const VerticalList = gui.VerticalList;
const HorizontalList = gui.HorizontalList;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 64},
	.hasBackground = true,
	.closeable = false,
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
};

const padding: f32 = 8;
pub fn update() void {
	if(main.Window.Gamepad.wereControllerMappingsDownloaded()) {
		gui.closeWindowFromRef(&window);
	}
}
pub fn onOpen() void {
	const label = Label.init(.{padding, 16 + padding}, 128, "Downloading controller mappings...", .center);
	window.rootComponent = label.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
