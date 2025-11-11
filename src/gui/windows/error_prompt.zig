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

var errorCount: u32 = 0;
var errorText: []const u8 = "";
var fileExplorerIcon: Texture = undefined;
var isOpen: bool = false;

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
	errorText = main.globalAllocator.dupe(u8, "");
}

pub fn deinit() void {
	fileExplorerIcon.deinit();
	main.globalAllocator.free(errorText);
}

fn openLog(_: usize) void {
	main.files.openDirInWindow("logs");
}

pub fn raiseError(newText: []const u8) void {
	if(isOpen) {
		errorCount += 1;
		onClose();
		onOpen();
	} else {
		main.globalAllocator.free(errorText);
		errorText = main.globalAllocator.dupe(u8, newText);
		errorCount = 0;
		gui.openWindowFromRef(&window);
	}
}

const padding: f32 = 8;
pub fn update() void {
	if(main.Window.Gamepad.wereControllerMappingsDownloaded()) {
		gui.closeWindowFromRef(&window);
	}
}

const plainErrorText = "#ffff00The game encountered errors.\nCheck the logs for details.";
const singleErrorFmtText = "#ff0000{s}";
const multipleErrorFmtText = "#ff0000{s}\n#ffff00And {d} more...\nCheck the logs for details.";

pub fn onOpen() void {
	isOpen = true;
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	var buf: [256]u8 = undefined;
	const str = if(errorCount == 0) std.fmt.bufPrint(&buf, singleErrorFmtText, .{errorText}) catch plainErrorText
		else std.fmt.bufPrint(&buf, multipleErrorFmtText, .{errorText, errorCount}) catch plainErrorText;
	list.add(Label.init(.{padding, 16 + padding}, 256, str, .center));
	list.add(Button.initIcon(.{0, 0}, .{16, 16}, fileExplorerIcon, false, .{.callback = &openLog}));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	isOpen = false;
	if(window.rootComponent) |*comp| {
		comp.deinit();
	}
}
