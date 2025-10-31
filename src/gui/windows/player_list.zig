const std = @import("std");

const main = @import("../../main.zig");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;
const TaskType = main.utils.ThreadPool.TaskType;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub fn onOpen() void {
	main.threadPool.performance.clear();
}

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .lower, .otherAttachmentPoint = .lower}},
	},
	.contentSize = Vec2f{128, 16},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

pub fn render() void {
	draw.setColor(0xffffffff);
	var y: f32 = 0;
	const dy = 8;

	if(main.server.world.?.allowPlayerList) {
		draw.print("__Player List__", .{}, 0, y, dy, .left);
		for(main.entity.ClientEntityManager.entities.items()) |ent| {
			draw.print("{s}", .{ent.name}, 0, y, dy, .left);
			y += dy;
		}
	}
}
