const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const draw = graphics.draw;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;
const TaskType = main.utils.ThreadPool.TaskType;
const vulkan = main.graphics.vulkan;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub fn onOpen() void {
	main.threadPool.performance.clear();
}

pub var window = GuiWindow{
	.relativePosition = .{
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
		.{.attachedToFrame = .{.selfAttachmentPoint = .upper, .otherAttachmentPoint = .upper}},
	},
	.contentSize = Vec2f{160, 8 + 8*std.meta.fieldNames(@TypeOf(vulkan.interestingExtensions)).len},
	.isHud = false,
	.showTitleBar = false,
	.hasBackground = false,
	.hideIfMouseIsGrabbed = false,
};

pub fn render() void {
	var y: f32 = 0;
	draw.print("Vulkan Version: {d}.{d}", .{vulkan.version.major, vulkan.version.minor}, 0, y, 8, .left);
	y += 8;
	inline for (comptime std.meta.fieldNames(@TypeOf(vulkan.interestingExtensions))) |extensionName| {
		if (@field(vulkan.interestingExtensions, extensionName)) {
			draw.print("{s} present", .{extensionName}, 0, y, 8, .left);
			y += 8;
		}
	}
}
