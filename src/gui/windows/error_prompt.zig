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

var overflowErrorCount: u32 = 0;
var errorText: ?[]const u8 = null;
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
}

pub fn deinit() void {
	fileExplorerIcon.deinit();
	if (errorText) |text| {
		main.globalAllocator.free(text);
		errorText = null;
	}
}

fn openLog() void {
	main.files.openDirInWindow("logs");
}

pub fn raiseError(newText: []const u8) void {
	if (isOpen) {
		overflowErrorCount += 1;
		onClose();
		onOpen();
	} else {
		if (errorText) |text| main.globalAllocator.free(text);
		errorText = main.globalAllocator.dupe(u8, newText);
		overflowErrorCount = 0;
		gui.openWindowFromRef(&window);
	}
}

const padding: f32 = 8;

const singleErrorFmtText = "#ff0000{s}";
const multipleErrorFmtText = "#ff0000{s}\n#ffff00And {d} more...\nCheck the logs for details.";

pub fn onOpen() void {
	isOpen = true;
	const list = VerticalList.init(.{padding, 16 + padding}, 300, 16);
	var str: []const u8 = undefined;
	if (overflowErrorCount == 0) {
		str = std.fmt.allocPrint(main.stackAllocator.allocator, singleErrorFmtText, .{errorText.?}) catch unreachable;
	} else {
		str = std.fmt.allocPrint(main.stackAllocator.allocator, multipleErrorFmtText, .{errorText.?, overflowErrorCount}) catch unreachable;
	}
	defer main.stackAllocator.free(str);
	list.add(Label.init(.{padding, 16 + padding}, 256, str, .center));
	list.add(Button.initIcon(.{0, 0}, .{16, 16}, fileExplorerIcon, false, .init(openLog)));
	list.finish(.center);
	window.rootComponent = list.toComponent();
	window.contentSize = window.rootComponent.?.pos() + window.rootComponent.?.size() + @as(Vec2f, @splat(padding));
	gui.updateWindowPositions();
}

pub fn onClose() void {
	isOpen = false;
	if (window.rootComponent) |*comp| {
		comp.deinit();
	}
}
