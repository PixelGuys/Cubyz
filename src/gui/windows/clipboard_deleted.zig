const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;
const TaskType = main.utils.ThreadPool.TaskType;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .middle, .otherAttachmentPoint = .middle}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{128, 16},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

var time: std.Io.Timestamp = undefined;

pub fn onOpen() void {
	time = main.timestamp();
}

pub fn render() void {
	const duration = time.durationTo(main.timestamp());
	if (duration.toSeconds() > 2) {
		gui.closeWindowFromRef(&window);
		return;
	}
	draw.setColor(0xffff8080);
	draw.print("Your clipboard was cleared.", .{}, 0, 0, 16, .left);
}
