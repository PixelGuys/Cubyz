const std = @import("std");
const Allocator = std.mem.Allocator;

const main = @import("root");
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiComponent = gui.GuiComponent;
const GuiWindow = gui.GuiWindow;

pub var window = GuiWindow {
	.contentSize = Vec2f{64*8, 64},
	.title = "Hotbar",
	.id = "cubyz:hotbar",
	.renderFn = &render,
	.components = &[_]GuiComponent{},
	.isHud = true,
};

pub fn render() Allocator.Error!void {

}