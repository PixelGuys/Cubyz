const std = @import("std");

const main = @import("main");
const files = main.files;
const settings = main.settings;
const Vec2f = main.vec.Vec2f;
const Texture = main.graphics.Texture;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const Label = @import("../components/Label.zig");
const VerticalList = @import("../components/VerticalList.zig");
const Button = @import("../components/Button.zig");

var fileExplorerIcon: Texture = undefined;

pub var window = GuiWindow{
	.contentSize = Vec2f{128, 64},
	.hasBackground = true,
	.hideIfMouseIsGrabbed = false,
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
	},
};

pub fn init() void {
	fileExplorerIcon = Texture.initFromFile("assets/cubyz/ui/file_explorer_icon.png");
}

pub fn deinit() void {
	fileExplorerIcon.deinit();
}

fn openLog(_: usize) void {
	main.files.openDirInWindow("logs");
}

const padding: f32 = 8;
pub fn update() void {
	if(main.Window.Gamepad.wereControllerMappingsDownloaded()) {
		gui.closeWindowFromRef(&window);
	}
}

pub fn onOpen() void {
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	list.add(Label.init(.{padding, 16 + padding}, 128, "#ffff00The game encountered errors. Check the logs for details", .center));
	list.add(Button.initIcon(.{0, 0}, .{16, 16}, fileExplorerIcon, false, .{.callback = &openLog}));
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
