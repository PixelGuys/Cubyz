const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

pub var window = GuiWindow {
	.contentSize = Vec2f{128, 16},
	.title = "Health Bar",
	.id = "cubyz:healthbar",
	.renderFn = &render,
	.isHud = true,
};

pub fn render() Allocator.Error!void {

}