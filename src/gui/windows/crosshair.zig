const std = @import("std");

const main = @import("main");
const graphics = main.graphics;
const Shader = graphics.Shader;
const Texture = graphics.Texture;
const Vec2f = main.vec.Vec2f;

const gui = @import("../gui.zig");
const GuiWindow = gui.GuiWindow;
const GuiComponent = gui.GuiComponent;

const c = main.graphics.c;

const size: f32 = 64;
pub var window = GuiWindow{
	.contentSize = Vec2f{size, size},
	.showTitleBar = false,
	.hasBackground = false,
	.isHud = true,
	.hideIfMouseIsGrabbed = false,
	.closeable = false,
};

var texture: Texture = undefined;

pub fn init() void {
	texture = Texture.initFromFile("assets/cubyz/ui/hud/crosshair.png");
}

pub fn deinit() void {
	texture.deinit();
}

pub fn render() void {
	texture.bindTo(0);
	graphics.draw.setColor(0xffffffff);
	c.glBlendFunc(c.GL_ONE, c.GL_ONE);
	c.glBlendEquation(c.GL_FUNC_SUBTRACT);
	graphics.draw.boundImage(.{0, 0}, .{size, size});
	c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
	c.glBlendEquation(c.GL_FUNC_ADD);
}
